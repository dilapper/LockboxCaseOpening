# Writes circle_hole.tga: a 512x512 black texture with a soft-edged transparent circle in the middle.
# The addon stretches it over the screen dimmer to make the "window" the spinner shows through.
# Usage: pwsh tools/make_circle_hole.ps1 <output-dir>
param([Parameter(Mandatory)][string]$Out)

$n = 512
$bytes = New-Object byte[] (18 + $n * $n * 4)
$bytes[2] = 2; $bytes[12] = $n -band 255; $bytes[13] = $n -shr 8; $bytes[14] = $n -band 255; $bytes[15] = $n -shr 8
$bytes[16] = 32; $bytes[17] = 0x28
$c = ($n - 1) / 2; $R = $n / 2 - 2; $feather = 16
for ($y = 0; $y -lt $n; $y++) {
    for ($x = 0; $x -lt $n; $x++) {
        $d = [math]::Sqrt(($x - $c) * ($x - $c) + ($y - $c) * ($y - $c))
        $t = [math]::Min(1, [math]::Max(0, ($d - ($R - $feather)) / $feather))
        $a = $t * $t * (3 - 2 * $t)
        $bytes[18 + ($y * $n + $x) * 4 + 3] = [byte][math]::Round($a * 255)
    }
}
New-Item -ItemType Directory -Force $Out | Out-Null
$path = Join-Path (Resolve-Path $Out).Path "circle_hole.tga"
[IO.File]::WriteAllBytes($path, $bytes)
Get-Item $path | Select-Object Name, Length
