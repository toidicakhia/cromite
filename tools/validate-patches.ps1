param(
    [string]$PatchesDir = "D:\cromite\build\patches",
    [string]$ListFile = "D:\cromite\build\cromite_patches_list_combined.txt"
)

Write-Host "=== PATCH VALIDATION REPORT ===" -ForegroundColor Cyan
Write-Host ""

$errors = @()
$warnings = @()

# 1. Validate all referenced patches exist
Write-Host "1) Checking patch references..." -ForegroundColor Yellow
if (Test-Path $ListFile) {
    $list = Get-Content $ListFile
    $patchRefs = $list | Where-Object { $_ -match '\.patch$' }
    $missing = @()
    foreach ($ref in $patchRefs) {
        $path = Join-Path $PatchesDir $ref
        if (-not (Test-Path $path)) {
            $missing += $ref
        }
    }
    if ($missing.Count -eq 0) {
        Write-Host "   All $($patchRefs.Count) patch references exist" -ForegroundColor Green
    } else {
        Write-Host "   $($missing.Count) patches missing!" -ForegroundColor Red
        $errors += "Missing patches: $($missing -join ', ')"
    }
}

# 2. Validate patch file syntax
Write-Host "`n2) Checking patch syntax..." -ForegroundColor Yellow
$allPatches = Get-ChildItem $PatchesDir -Filter "*.patch" | Where-Object { $_.Name -notmatch '\.bak$' }

$validCount = 0
$invalidCount = 0
foreach ($f in $allPatches) {
    $content = Get-Content $f.FullName -Raw
    
    # Check it has From/Date/Subject header (multiline matching)
    $hasFrom = [regex]::IsMatch($content, '^From:', 'Multiline')
    $hasDate = [regex]::IsMatch($content, '^Date:', 'Multiline')
    $hasSubject = [regex]::IsMatch($content, '^Subject:', 'Multiline')
    
    # Count diff sections
    $diffCount = [regex]::Matches($content, '^diff --git', 'Multiline').Count
    $hunkCount = [regex]::Matches($content, '^@@ -\d+,\d+ +\+\d+,\d+', 'Multiline').Count
    
    # Check for common issues
    $issues = @()
    if (-not $hasFrom) { $issues += "missing From:" }
    if (-not $hasDate) { $issues += "missing Date:" }
    if (-not $hasSubject) { $issues += "missing Subject:" }
    if ($diffCount -eq 0 -and $hunkCount -eq 0) { $issues += "no diffs (empty patch)" }
    
    if ($issues.Count -eq 0) {
        $validCount++
    } else {
        $invalidCount++
        $warnings += "$($f.Name): $($issues -join ', ')"
    }
}
Write-Host "   Valid: $validCount, Issues: $invalidCount" -ForegroundColor $(if($invalidCount -eq 0){"Green"}else{"Yellow"})

# 3. Check for duplicate entries
Write-Host "`n3) Checking for duplicate entries..." -ForegroundColor Yellow
$allListFiles = @(
    "D:\cromite\build\cromite_patches_list.txt",
    "D:\cromite\build\cromite_patches_list_7.txt",
    "D:\cromite\build\cromite_patches_list_combined.txt"
)
foreach ($lf in $allListFiles) {
    if (Test-Path $lf) {
        $entries = Get-Content $lf | Where-Object { $_ -match '\.patch$' -and $_ -notmatch '^#' }
        $dupes = $entries | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($dupes.Count -gt 0) {
            Write-Host "   $($lf): $($dupes.Count) duplicates found" -ForegroundColor Red
            $dupes | ForEach-Object { Write-Host "     $($_.Name) ($($_.Count)x)" }
            $errors += "Duplicates in $lf"
        } else {
            Write-Host "   $($lf): OK" -ForegroundColor Green
        }
    }
}

# 4. Check for cross-references between lists
Write-Host "`n4) Checking main list for WIN7 references..." -ForegroundColor Yellow
$mainList = Get-Content "D:\cromite\build\cromite_patches_list.txt"
$win7refs = $mainList | Where-Object { $_ -match '-win\.patch|WIN7|windows.?7|win.?7' }
if ($win7refs.Count -gt 0) {
    Write-Host "   Found Win7 references in main list: $($win7refs -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "   Main list is clean" -ForegroundColor Green
}

# 5. Summary
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total patch files: $($allPatches.Count)" -ForegroundColor White
Write-Host "Errors: $($errors.Count)" -ForegroundColor $(if($errors.Count -eq 0){"Green"}else{"Red"})
Write-Host "Warnings: $($warnings.Count)" -ForegroundColor $(if($warnings.Count -eq 0){"Green"}else{"Yellow"})

if ($errors.Count -gt 0) {
    Write-Host "`nErrors:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  $_" }
}
if ($warnings.Count -gt 0) {
    Write-Host "`nWarnings:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  $_" }
}
