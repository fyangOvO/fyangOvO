Add-Type -AssemblyName System.Drawing
$root='D:\七傳說'
$base=Join-Path $root 'game\assets\backgrounds\backdrop_forest_640x360.png'
$back=[System.Drawing.Image]::FromFile($base)
$warrior= [System.Drawing.Image]::FromFile((Join-Path $root 'game\assets\previews\warrior_attack_s.gif'))
$enemy=[System.Drawing.Image]::FromFile((Join-Path $root 'game\assets\previews\skeleton_attack.gif'))
$slash=[System.Drawing.Image]::FromFile((Join-Path $root 'game\assets\anim\slash.gif'))
$burst=[System.Drawing.Image]::FromFile((Join-Path $root 'game\assets\anim\fireburst.gif'))
$out=Join-Path $root 'deliverables\gstack\策划案\character_attack_preview_v1.gif'
$td=[System.Drawing.Imaging.FrameDimension]::Time

function CopyFrame([System.Drawing.Image]$img,[int]$idx){
  try { $null=$img.SelectActiveFrame($td,$idx) } catch { throw "Could not select animation frame $idx (frames=$($img.GetFrameCount($td)), source=$($img.Width)x$($img.Height)): $($_.Exception.Message)" }
  $b=[System.Drawing.Bitmap]::new($img.Width,$img.Height)
  $g=[System.Drawing.Graphics]::FromImage($b);$g.DrawImage($img,0,0,$img.Width,$img.Height);$g.Dispose()
  $key=$b.GetPixel(0,0)
  for($yy=0;$yy -lt $b.Height;$yy++){for($xx=0;$xx -lt $b.Width;$xx++){$c=$b.GetPixel($xx,$yy);$dr=[Math]::Abs($c.R-$key.R);$dg=[Math]::Abs($c.G-$key.G);$db=[Math]::Abs($c.B-$key.B);if($dr -le 9 -and $dg -le 9 -and $db -le 9){$b.SetPixel($xx,$yy,[System.Drawing.Color]::FromArgb(0,$c.R,$c.G,$c.B))}}}
  return ,$b
}
function PaintSprite([System.Drawing.Bitmap]$canvas,[System.Drawing.Image]$img,[int]$idx,[System.Drawing.Rectangle]$dest,[bool]$flash=$false){
  $b=CopyFrame $img $idx
  if($flash){for($yy=0;$yy -lt $b.Height;$yy++){for($xx=0;$xx -lt $b.Width;$xx++){$c=$b.GetPixel($xx,$yy);if($c.A -gt 0){$v=[Math]::Max($c.R,[Math]::Max($c.G,$c.B));$b.SetPixel($xx,$yy,[System.Drawing.Color]::FromArgb($c.A,[Math]::Min(255,$v+90),[Math]::Min(255,$v+90),[Math]::Min(255,$v+90)))}}}}
  $key=$b.GetPixel(0,0)
  for($yy=0;$yy -lt $b.Height;$yy++){
    $ty=$dest.Y+[int][Math]::Floor($yy*$dest.Height/$b.Height)
    for($xx=0;$xx -lt $b.Width;$xx++){
      $c=$b.GetPixel($xx,$yy)
      if($c.A -eq 0 -or ($c.R -le $key.R+9 -and $c.R -ge $key.R-9 -and $c.G -le $key.G+9 -and $c.G -ge $key.G-9 -and $c.B -le $key.B+9 -and $c.B -ge $key.B-9)){continue}
      $tx=$dest.X+[int][Math]::Floor($xx*$dest.Width/$b.Width)
      if($tx -ge 0 -and $tx -lt $canvas.Width -and $ty -ge 0 -and $ty -lt $canvas.Height){$canvas.SetPixel($tx,$ty,$c)}
    }
  }
  $b.Dispose()
}

$wf=$warrior.GetFrameCount($td);$ef=$enemy.GetFrameCount($td);$sf=$slash.GetFrameCount($td);$bf=$burst.GetFrameCount($td)
$frames=New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
for($i=0;$i -lt 16;$i++){
  $canvas=[System.Drawing.Bitmap]::new(640,360);$g=[System.Drawing.Graphics]::FromImage($canvas)
  $g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
  $g.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $g.DrawImage($back,0,0,640,360)
  # Small cinematic shade keeps the silhouettes and hit effect readable.
  $veil=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(65,7,10,17));$g.FillRectangle($veil,0,0,640,360);$veil.Dispose()
  # Dust puffs at the feet, expanding and fading through the swing.
  for($d=0;$d -lt 7;$d++){
    $phase=($i+$d*2)%16;$r=5+[Math]::Min(15,$phase)
    $alpha=[Math]::Max(0,95-$phase*6)
    if($alpha -gt 0){$brush=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($alpha,171,177,157));$g.FillEllipse($brush,197+$d*6-$r/2,260-$r/3,$r,$r/2);$brush.Dispose()}
  }
  # Keep the combatants grounded on one shared floor plane.
  PaintSprite $canvas $warrior (([int][Math]::Floor($i/2))%$wf) ([System.Drawing.Rectangle]::new(195,83,174,174))
  $hit=($i -ge 7 -and $i -le 9)
  PaintSprite $canvas $enemy (([int][Math]::Floor($i/3))%$ef) ([System.Drawing.Rectangle]::new(342,111,145,145)) $hit
  # Main sword arc sweeps across the enemy during the active frames.
  if($i -ge 4 -and $i -le 11){PaintSprite $canvas $slash (($i-4)%$sf) ([System.Drawing.Rectangle]::new(292,115,108,108))}
  if($i -ge 7 -and $i -le 9){PaintSprite $canvas $burst (($i-7)%$bf) ([System.Drawing.Rectangle]::new(355,139,70,70))}
  # Discrete pixel sparks follow the direction of the sword swing.
  if($i -ge 6 -and $i -le 10){
    $rng=[Random]::new(121+$i)
    for($p=0;$p -lt 20;$p++){
      $x=355+$rng.Next(0,85);$y=145+$rng.Next(-30,60);$w=2+$rng.Next(0,3)
      $color=if($p%4 -eq 0){[System.Drawing.Color]::FromArgb(255,255,232,150)}elseif($p%4 -eq 1){[System.Drawing.Color]::FromArgb(255,173,225,255)}else{[System.Drawing.Color]::FromArgb(255,255,255,230)}
      $brush=[System.Drawing.SolidBrush]::new($color);$g.FillRectangle($brush,$x,$y,$w,$w);$brush.Dispose()
    }
  }
  $g.Dispose();$canvas.SetResolution(96,96);$frames.Add($canvas)
}
$codec=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()|Where-Object{$_.MimeType -eq 'image/gif'}
$ep=[System.Drawing.Imaging.EncoderParameters]::new(1)
$ep.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::MultiFrame)
$frames[0].Save($out,$codec,$ep)
$ep.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::FrameDimensionTime)
for($i=1;$i -lt $frames.Count;$i++){$frames[0].SaveAdd($frames[$i],$ep)}
$ep.Param[0]=[System.Drawing.Imaging.EncoderParameter]::new([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::Flush);$frames[0].SaveAdd($ep)
foreach($f in $frames){$f.Dispose()};$warrior.Dispose();$enemy.Dispose();$slash.Dispose();$burst.Dispose();$back.Dispose();Write-Output $out
