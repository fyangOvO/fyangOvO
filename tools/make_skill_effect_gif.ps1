Add-Type -AssemblyName System.Drawing

$root = 'D:\七傳說'
$bgPath = Join-Path $root 'game\assets\previews\scene_preview_2x.png'
$fxPath = Join-Path $root 'game\assets\anim\slash.gif'
$outPath = Join-Path $root 'deliverables\gstack\策划案\skill_effect_slash_preview_v1.gif'

$bg = [System.Drawing.Bitmap]::new($bgPath)
$fx = [System.Drawing.Image]::FromFile($fxPath)
$dim = [System.Drawing.Imaging.FrameDimension]::Time
$count = $fx.GetFrameCount($dim)
$frames = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]

for ($i = 0; $i -lt $count; $i++) {
  $fx.SelectActiveFrame($dim, $i)
  $frame = [System.Drawing.Bitmap]::new(640, 360)
  $g = [System.Drawing.Graphics]::FromImage($frame)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $g.DrawImage($bg, 0, 0, 640, 360)
  $shade = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(120, 0, 0, 0))
  $g.FillRectangle($shade, 0, 0, 640, 360)
  $fxFrame = [System.Drawing.Bitmap]::new($fx.Width, $fx.Height)
  $fg = [System.Drawing.Graphics]::FromImage($fxFrame)
  $fg.DrawImage($fx, 0, 0, $fx.Width, $fx.Height)
  $fg.Dispose()
  for ($py = 0; $py -lt $fxFrame.Height; $py++) {
    for ($px = 0; $px -lt $fxFrame.Width; $px++) {
      $c = $fxFrame.GetPixel($px, $py)
      if ($c.R -lt 24 -and $c.G -lt 24 -and $c.B -lt 24) {
        $fxFrame.SetPixel($px, $py, [System.Drawing.Color]::FromArgb(0, $c.R, $c.G, $c.B))
      }
    }
  }
  $g.DrawImage($fxFrame, [System.Drawing.Rectangle]::new(248, 112, 144, 144))
  $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(212, 192, 126), 2)
  $g.DrawRectangle($pen, 18, 18, 604, 324)
  $font = [System.Drawing.Font]::new('Microsoft JhengHei UI', 18, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $small = [System.Drawing.Font]::new('Microsoft JhengHei UI', 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString('裂斬  ·  技能動效草稿', $font, [System.Drawing.Brushes]::White, 34, 30)
  $g.DrawString(('Frame {0}/{1}  ·  斬擊弧光 / 命中閃白 / 短暫拖尾' -f ($i+1), $count), $small, [System.Drawing.Brushes]::LightGray, 34, 310)
  $fxFrame.Dispose(); $g.Dispose(); $shade.Dispose(); $pen.Dispose(); $font.Dispose(); $small.Dispose()
  $frames.Add($frame)
}

$encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/gif' }
$ep = [System.Drawing.Imaging.EncoderParameters]::new(1)
$ep.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag, [long][System.Drawing.Imaging.EncoderValue]::MultiFrame)
$frames[0].Save($outPath, $encoder, $ep)
$ep.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag, [long][System.Drawing.Imaging.EncoderValue]::FrameDimensionTime)
for ($i = 1; $i -lt $frames.Count; $i++) { $frames[0].SaveAdd($frames[$i], $ep) }
$ep.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag, [long][System.Drawing.Imaging.EncoderValue]::Flush)
$frames[0].SaveAdd($ep)

foreach ($f in $frames) { $f.Dispose() }
$fx.Dispose(); $bg.Dispose()
Write-Output $outPath
