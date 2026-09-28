Add-Type -AssemblyName System.Drawing
$root='D:\七傳說'
$bg=[System.Drawing.Bitmap]::new((Join-Path $root 'game\assets\previews\scene_preview_2x.png'))
$slash=[System.Drawing.Image]::FromFile((Join-Path $root 'game\assets\anim\slash.gif'))
$burst=[System.Drawing.Image]::FromFile((Join-Path $root 'game\assets\anim\fireburst.gif'))
$out=Join-Path $root 'deliverables\gstack\策划案\skill_effect_slash_preview_v2.gif'
$td=[System.Drawing.Imaging.FrameDimension]::Time
$frames=New-Object System.Collections.Generic.List[System.Drawing.Bitmap]

function FxFrame($img,$idx) {
  $null = $img.SelectActiveFrame($td,$idx)
  $b=[System.Drawing.Bitmap]::new($img.Width,$img.Height)
  $gx=[System.Drawing.Graphics]::FromImage($b); $gx.DrawImage($img,0,0,$img.Width,$img.Height); $gx.Dispose()
  for($y=0;$y -lt $b.Height;$y++){ for($x=0;$x -lt $b.Width;$x++){ $c=$b.GetPixel($x,$y); if($c.R -lt 28 -and $c.G -lt 28 -and $c.B -lt 28){$b.SetPixel($x,$y,[System.Drawing.Color]::FromArgb(0,$c.R,$c.G,$c.B))} } }
  return $b
}

$slashN=$slash.GetFrameCount($td); $burstN=$burst.GetFrameCount($td)
for($i=0;$i -lt 18;$i++){
  $im=[System.Drawing.Bitmap]::new(640,360); $g=[System.Drawing.Graphics]::FromImage($im)
  $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.DrawImage($bg,0,0,640,360)
  $g.FillRectangle([System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(105,0,0,0)),0,0,640,360)
  $pen=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(210,192,126),2); $g.DrawRectangle($pen,18,18,604,324)
  $cx=322; $cy=186
  # ground feedback ring and impact glow
  $ringA=[Math]::Max(0,150-(($i-6)*14)); $ringR=28+[Math]::Min(54,$i*5)
  if($ringA -gt 0){$g.DrawEllipse([System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb($ringA,94,190,255),3),$cx-$ringR,$cy+18-$ringR/3,$ringR*2,$ringR/2)}
  # afterimages, primary slash, and fire burst core
  $sf=FxFrame $slash ($i%$slashN); $bf=FxFrame $burst ($i%$burstN)
  if($i -ge 3){$g.DrawImage($sf,[System.Drawing.Rectangle]::new(210,104,144,144))}
  $g.DrawImage($sf,[System.Drawing.Rectangle]::new(250,108,144,144))
  if($i -ge 6 -and $i -le 12){$g.DrawImage($bf,[System.Drawing.Rectangle]::new(294,143,58,58))}
  $sf.Dispose();$bf.Dispose()
  # hand-placed pixel sparks around the impact point
  $rand=[Random]::new(900+$i)
  for($p=0;$p -lt 24;$p++){
    $ang=$rand.NextDouble()*6.283; $dist=24+$rand.NextDouble()*(18+$i*5); $len=3+$rand.Next(0,10)
    $x1=$cx+[Math]::Cos($ang)*$dist; $y1=$cy+[Math]::Sin($ang)*$dist
    $x2=$cx+[Math]::Cos($ang)*($dist+$len); $y2=$cy+[Math]::Sin($ang)*($dist+$len)
    $col=if($p%3 -eq 0){[System.Drawing.Color]::FromArgb(245,246,228,123)}elseif($p%3 -eq 1){[System.Drawing.Color]::FromArgb(220,120,210,255)}else{[System.Drawing.Color]::FromArgb(220,255,255,255)}
    $g.DrawLine([System.Drawing.Pen]::new($col,2),[float]$x1,[float]$y1,[float]$x2,[float]$y2)
  }
  $f=[System.Drawing.Font]::new('Microsoft JhengHei UI',18,[System.Drawing.FontStyle]::Bold,[System.Drawing.GraphicsUnit]::Pixel)
  $s=[System.Drawing.Font]::new('Microsoft JhengHei UI',12,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Pixel)
  $g.DrawString('裂斬  ·  精緻動效草稿 V2',$f,[System.Drawing.Brushes]::White,34,30)
  $g.DrawString(('分層：主斬擊 / 殘影 / 命中閃光 / 火花 / 地面回饋   Frame {0}/18' -f ($i+1)),$s,[System.Drawing.Brushes]::LightGray,34,310)
  $g.Dispose();$pen.Dispose();$f.Dispose();$s.Dispose();$frames.Add($im)
}

$codec=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object{$_.MimeType -eq 'image/gif'}
$ep=[System.Drawing.Imaging.EncoderParameters]::new(1)
$ep.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::MultiFrame)
$frames[0].Save($out,$codec,$ep)
$ep.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::FrameDimensionTime)
for($i=1;$i -lt $frames.Count;$i++){$frames[0].SaveAdd($frames[$i],$ep)}
$ep.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::Flush);$frames[0].SaveAdd($ep)
foreach($f in $frames){$f.Dispose()};$slash.Dispose();$burst.Dispose();$bg.Dispose();Write-Output $out
