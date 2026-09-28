Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue

$root = 'D:\七傳說'
$bgPath = Join-Path $root 'game\assets\previews\scene_preview_2x.png'
$fontPath = Join-Path $root 'game\assets\fonts\Cubic_11.ttf'
$iconPath = Join-Path $root 'game\assets\ui\skill_icons\skill_slash_48.png'
$outPath = Join-Path $root 'deliverables\gstack\策划案\skill_concept_preview_v1.png'

$bmp = [System.Drawing.Bitmap]::new($bgPath)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

$panelBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(238, 16, 20, 29))
$panelBrush2 = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(232, 22, 27, 38))
$gold = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(210, 194, 135), 3)
$goldThin = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(145, 128, 75), 2)
$blue = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(82, 158, 235), 2)
$purple = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(170, 103, 225), 2)
$white = [System.Drawing.Brushes]::White
$muted = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(185, 194, 205))
$cyan = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(116, 209, 255))
$amber = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(238, 193, 91))

function Font([float]$size, [System.Drawing.FontStyle]$style = [System.Drawing.FontStyle]::Regular) {
  $f = [System.Drawing.Font]::new('Microsoft JhengHei UI', $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
  return $f
}
function Text($s, $x, $y, $size, $brush, $style = [System.Drawing.FontStyle]::Regular) {
  $g.DrawString($s, (Font $size $style), $brush, [float]$x, [float]$y)
}
function Box($x,$y,$w,$h,$brush,$pen=$null) {
  $g.FillRectangle($brush,$x,$y,$w,$h)
  if ($pen) { $g.DrawRectangle($pen,$x,$y,$w,$h) }
}

# Overlay dims the combat scene but keeps the pixel-art silhouette visible.
$dim = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(125, 0, 0, 0))
$g.FillRectangle($dim,0,0,$bmp.Width,$bmp.Height)

# Main skill panel.
Box 270 55 740 610 $panelBrush $gold
Box 292 78 696 74 $panelBrush2 $goldThin
Text '技能詳情' 320 91 28 $white ([System.Drawing.FontStyle]::Bold)
Text '裂斬  ·  戰士  ·  SINGLE' 320 122 18 $muted
Text 'Lv. 7 / 10' 835 96 18 $amber ([System.Drawing.FontStyle]::Bold)
Text '倍率  ×1.48   冷卻  6.0s   藍耗  30' 835 123 14 $muted

# Left description card.
Box 305 175 300 188 $panelBrush2 $goldThin
Text '技能預覽' 326 192 18 $amber ([System.Drawing.FontStyle]::Bold)
$icon = [System.Drawing.Bitmap]::new($iconPath)
$g.DrawImage($icon, [System.Drawing.Rectangle]::new(330,225,96,96))
Text '向前方揮出猛烈一擊。' 448 226 16 $white
Text '命中最近目標並造成物理傷害。' 448 254 14 $muted
Text '技能等級提高倍率，' 448 282 14 $cyan
Text '不改變冷卻與範圍。' 448 306 14 $cyan

# Rune sockets.
Text '符文槽  (解鎖：Lv.3 / 6 / 9)' 632 178 18 $amber ([System.Drawing.FontStyle]::Bold)
for ($i=0; $i -lt 3; $i++) {
  $x = 650 + ($i * 102)
  Box $x 218 82 82 $panelBrush2 $blue
  if ($i -eq 0) { Text '彈道化' ($x+10) 246 15 $cyan ([System.Drawing.FontStyle]::Bold); Text 'PROJECTILE' ($x+8) 273 10 $muted }
  elseif ($i -eq 1) { Text '熾焰' ($x+18) 246 15 ([System.Drawing.SolidBrush]::new([System.Drawing.Color]::OrangeRed)) ([System.Drawing.FontStyle]::Bold); Text '+15% 火焰' ($x+8) 273 10 $muted }
  else { Text '+' ($x+32) 237 30 $muted ([System.Drawing.FontStyle]::Bold); Text '空槽' ($x+24) 273 11 $muted }
}
Text '互斥組：形態 1 / 元素 1 / 行為 1' 650 324 13 $muted

# Form branch section.
Box 305 392 700 232 $panelBrush2 $goldThin
Text '形態分支  ·  Lv.5 解鎖（二選一）' 330 410 19 $amber ([System.Drawing.FontStyle]::Bold)
Text '目前形態：單體 SINGLE' 330 440 14 $muted
Box 330 470 300 112 ([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(80, 40, 66, 94))) $blue
Box 680 470 300 112 ([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(70, 62, 38, 88))) $purple
Text 'A  專注' 352 487 19 $cyan ([System.Drawing.FontStyle]::Bold)
Text '倍率 +40%' 352 520 18 $white
Text '更高單體爆發，適合首領戰。' 352 551 13 $muted
Text 'B  連擊' 702 487 19 ([System.Drawing.SolidBrush]::new([System.Drawing.Color]::Violet)) ([System.Drawing.FontStyle]::Bold)
Text '追加一段 60% 傷害' 702 520 18 $white
Text '連續命中，適合清理精英群。' 702 551 13 $muted

# Footer.
Text '預覽稿 V1  ·  以現有像素資產與 UI 金邊規範製作' 310 686 13 $muted
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $icon.Dispose()
Write-Output $outPath
