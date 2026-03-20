
$url = "https://www.knue.ac.kr/www/selectSearchEmplList.do?key=444&searchKrwd=043"
$html = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent "Mozilla/5.0" -TimeoutSec 30
$content = $html.Content

$rows = [regex]::Matches($content, '<tr>(.*?)</tr>', 'Singleline')
$results = [System.Collections.ArrayList]@()

function CleanHtml($s) {
    $s = [regex]::Replace($s, '<[^>]+>', '')
    $s = $s -replace '&amp;', '&'
    $s = $s -replace '&nbsp;', ' '
    $s = [regex]::Replace($s, '\s+', ' ')
    return $s.Trim()
}

foreach ($row in $rows) {
    $rowHtml = $row.Value
    if ($rowHtml -notmatch '<td') { continue }

    $tds = [regex]::Matches($rowHtml, '<td[^>]*>(.*?)</td>', 'Singleline')
    if ($tds.Count -lt 4) { continue }

    $cat   = CleanHtml($tds[0].Groups[1].Value)
    $dept  = CleanHtml($tds[1].Groups[1].Value)
    $duty  = CleanHtml($tds[2].Groups[1].Value)
    $phoneMatch = [regex]::Match($rowHtml, '043-[\d-]+')
    if ($phoneMatch.Success) {
        $phone = $phoneMatch.Value
    } else {
        $phone = ""
    }

    $obj = [PSCustomObject]@{
        category = $cat
        dept     = $dept
        duties   = $duty
        phone    = $phone
    }
    [void]$results.Add($obj)
}

Write-Host "파싱 결과: $($results.Count)건"
$results | Select-Object -First 3 | Format-Table -AutoSize

$json = $results | ConvertTo-Json -Depth 3
Set-Content -Path "knue_staff.json" -Value $json -Encoding UTF8
Write-Host "knue_staff.json 저장 완료"
