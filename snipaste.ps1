$pinvoke = @"
using System;
using System.Runtime.InteropServices;
namespace Win32
{
    public static class NativeMethods
    {

        public const int S_OK = 0;

        // https://learn.microsoft.com/en-us/windows/win32/api/shellscalingapi/ne-shellscalingapi-process_dpi_awareness
        public enum PROCESS_DPI_AWARENESS
        {
            PROCESS_DPI_UNAWARE = 0,
            PROCESS_SYSTEM_DPI_AWARE = 1,
            PROCESS_PER_MONITOR_DPI_AWARE = 2
        }

        // https://learn.microsoft.com/en-us/windows/win32/api/shellscalingapi/nf-shellscalingapi-getprocessdpiawareness
        [DllImport("Shcore.dll")]
        public static extern int GetProcessDpiAwareness(
            IntPtr hprocess,
            ref PROCESS_DPI_AWARENESS value
        );

        // https://learn.microsoft.com/en-us/windows/win32/api/shellscalingapi/nf-shellscalingapi-setprocessdpiawareness
        [DllImport("Shcore.dll")]
        public static extern int SetProcessDpiAwareness(
            PROCESS_DPI_AWARENESS value
        );

    }
}
"@;

Add-Type -TypeDefinition $pinvoke;

$dpiAwareness = "PROCESS_PER_MONITOR_DPI_AWARE";
$hresult = [Win32.NativeMethods]::GetProcessDpiAwareness([IntPtr]::Zero, [ref] $dpiAwareness);
if( $hresult -ne [Win32.NativeMethods]::S_OK )
{
    throw "failed to get dpi awareness with hresult '$hresult'";
}
write-host "current DPI Awareness = $dpiAwareness";

# this will return -2147024891 => 0x80070005 => E_ACCESSDENIED if called more than once
$hresult = [Win32.NativeMethods]::SetProcessDpiAwareness("PROCESS_PER_MONITOR_DPI_AWARE");
if( $hresult -ne [Win32.NativeMethods]::S_OK )
{
    throw "failed to set dpi awareness with hresult '$hresult'";
}



Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create form and set properties
$form = New-Object System.Windows.Forms.Form
$form.Text = "Snipaste"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.TopMost = $true
$form.FormBorderStyle = "None"
# $form.AutoScale = $true
# $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(2724, 2272) # 设置DPI为96
# $form.AutoScaleMode = 'dpi'

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 10)
$label.Size = New-Object System.Drawing.Size(400, 300)
# $label.Dock = 'Center'
$label.Text = "INSTRUCTIONS:`n1. Alt+S to capture RIO.`n2. Alt+Q to minimize.`n3. Scroll to scale.`n4. Escape to quit."
$font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$label.Font = $font
$form.Controls.Add($label)

# Create picture frame and set properties
$pictureFrame = New-Object System.Windows.Forms.PictureBox
$pictureFrame.Dock = "Fill"
$pictureFrame.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::StretchImage
$form.Controls.Add($pictureFrame)

$global:bitmap = $null

# get screen's width and height, if necessary
# $mainScreen = [System.Windows.Forms.Screen]::PrimaryScreen
# $screenWidth = $mainScreen.Bounds.Width
# $screenHeight = $mainScreen.Bounds.Height

# Add mouse wheel event to zoom in/out the picture
$pictureFrame.Add_MouseWheel({
        # Zoom out
        if ($_.Delta -gt 0) {
            # Write-Host "pictureFrame widthxheight: ", $pictureFrame.Width, $pictureFrame.Height
            $pictureFrame.Width *= 1.1
            $pictureFrame.Height *= 1.1
            $form.Width *= 1.1
            $form.Height *= 1.1
        }
        # Zoom in
        else {
            $pictureFrame.Width /= 1.1
            $pictureFrame.Height /= 1.1
            $form.Width /= 1.1
            $form.Height /= 1.1
        }
    })

$form.Add_KeyDown({
        # Alt+S: snipaste function
        if ($_.KeyCode -eq "S" -and $_.Modifiers -eq "Alt") {
            # Hide form temporarily to allow user to select screen region
            $form.Hide()
            $label.Hide()

            # Prompt user to select screen region
            $region = [System.Windows.Forms.Screen]::GetBounds([System.Drawing.Point]::Empty)
            $regionSelector = New-Object System.Drawing.RectangleF($region.Left, $region.Top, $region.Width, $region.Height)
            $selectorForm = New-Object System.Windows.Forms.Form
            $selectorForm.FormBorderStyle = "None"
            $selectorForm.WindowState = "Maximized"
            $selectorForm.BackColor = "Black"
            $selectorForm.Opacity = 0.2
            $selectorForm.TopMost = $true
            $selectorForm.Add_Paint({
                    $selectorForm.CreateGraphics().DrawRectangle([System.Drawing.Pens]::Red, $regionSelector.X, $regionSelector.Y, $regionSelector.Width, $regionSelector.Height)
                })
        
            $selectorForm.Add_MouseDown({
                    $regionSelector.X = [System.Windows.Forms.Cursor]::Position.X
                    $regionSelector.Y = [System.Windows.Forms.Cursor]::Position.Y
                    # Write-Host "regionSeletor-1", $regionSelector.X, $regionSelector.Y
                })
        
            $selectorForm.Add_MouseMove({
                    if ([System.Windows.Forms.Control]::MouseButtons -eq "Left") {
                        $selectorForm.Opacity = 0.0
                        $regionSelector.Width = [System.Windows.Forms.Cursor]::Position.X - $regionSelector.X
                        $regionSelector.Height = [System.Windows.Forms.Cursor]::Position.Y - $regionSelector.Y
                        # Write-host "regionSelector size: ", $regionSelector.Width, $regionSelector.Height
                        $selectorForm.Invalidate()
                    }
                })

            $selectorForm.Add_MouseUp({
                    # Write-Host "release mouse", $regionSelector.Width, $regionSelector.Height
                    # Capture screen region and display in picture frame
                    if ($regionSelector.Width -gt 0 -and $regionSelector.Height -gt 0) {
                        $global:bitmap = New-Object System.Drawing.Bitmap([int]$regionSelector.Width, [int]$regionSelector.Height)
                        $graphics = [System.Drawing.Graphics]::FromImage($global:bitmap)
                        $graphics.CopyFromScreen($regionSelector.X, $regionSelector.Y, 0, 0, $global:bitmap.Size)
                        $pictureFrame.Image = $global:bitmap
                        # Copy bitmap to clipboard
                        [System.Windows.Forms.Clipboard]::SetImage($global:bitmap)

                    }
                    $selectorForm.Close()

                    $form.Width = $regionSelector.Width
                    $form.Height = $regionSelector.Height

                    # Show form again
                    $form.Show()
                })

            $selectorForm.Add_KeyDown({
                    if ($_.KeyCode -eq "Escape") {
                        $selectorForm.Close()
                    }
                    $form.Show()
                })
            $selectorForm.ShowDialog()
        }
    })

$form.Add_KeyDown({
        if ($_.KeyCode -eq "Q" -and $_.Alt) {
            $form.WindowState = "Minimized"
        }
        if ($_.KeyCode -eq "Escape") {
            $form.Close()
        }
    })


$global:formTop = $form.Top
$global:formLeft = $form.Left
$global:mouseDownPoint = $null

$pictureFrame.Add_MouseDown({
    $global:mouseDownPoint = [System.Windows.Forms.Cursor]::Position
    $global:formTop = $form.Top
    $global:formLeft = $form.Left
})

$pictureFrame.Add_MouseMove({$currentMousePoint
    if ([System.Windows.Forms.Control]::MouseButtons -eq "Left") {
        $currentMousePoint = [System.Windows.Forms.Cursor]::Position
        $deltaX = $currentMousePoint.X - $global:mouseDownPoint.X
        $deltaY = $currentMousePoint.Y - $global:mouseDownPoint.Y
        $form.Top = $global:formTop + $deltaY
        $form.Left = $global:formLeft + $deltaX
    }
})

$label.Add_MouseDown({
    $global:mouseDownPoint = [System.Windows.Forms.Cursor]::Position
    $global:formTop = $form.Top
    $global:formLeft = $form.Left
})

$label.Add_MouseMove({
    if ([System.Windows.Forms.Control]::MouseButtons -eq "Left") {
        $currentMousePoint = [System.Windows.Forms.Cursor]::Position
        $deltaX = $currentMousePoint.X - $global:mouseDownPoint.X
        $deltaY = $currentMousePoint.Y - $global:mouseDownPoint.Y
        $form.Top = $global:formTop + $deltaY
        $form.Left = $global:formLeft + $deltaX
    }
})

# Show the form
$form.ShowDialog() | Out-Null
$form.Dispose()
