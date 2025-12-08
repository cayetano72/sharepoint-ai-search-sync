<#
.SYNOPSIS
    Prepares code corpus from ZIP file(s) for Azure AI Search ingestion.

.DESCRIPTION
    Extracts code files from ZIP archives, filters by allowed extensions,
    creates metadata, and packages them for Azure AI Search indexing.

.PARAMETER ZipPath
    Path to the ZIP file or directory containing ZIP files

.PARAMETER ProjectName
    Name of the project (e.g., "Atlantis")

.PARAMETER ProjectCode
    Short code for the project (e.g., "ATL")

.PARAMETER OutputPath
    Output directory for the prepared corpus (default: .\code_corpus)

.PARAMETER AllowedExtensions
    Comma-separated list of file extensions to include (default: .cs,.js,.ts,.py,.java,.json,.xml,.yaml,.yml,.md)

.EXAMPLE
    .\Prepare-CodeCorpus.ps1 -ZipPath "C:\Code\atlpp-main.zip" -ProjectName "Atlantis" -ProjectCode "ATL" -OutputPath "C:\Output\code_corpus"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ZipPath,
    
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory=$true)]
    [string]$ProjectCode,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = ".\code_corpus",
    
    [Parameter(Mandatory=$false)]
    [string]$AllowedExtensions = ".cs,.js,.ts,.tsx,.jsx,.py,.java,.go,.rb,.php,.cpp,.c,.h,.hpp,.swift,.kt,.scala,.rs,.json,.xml,.yaml,.yml,.md,.txt,.sql,.sh,.ps1,.bat,.cmd"
)

# Configuration
$CHUNK_SIZE = 8000  # Maximum characters per chunk
$CHUNK_OVERLAP = 200  # Overlap between chunks

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-AllowedExtension {
    param([string]$FilePath)
    $extensions = $AllowedExtensions -split ","
    $fileExt = [System.IO.Path]::GetExtension($FilePath).ToLower()
    return $extensions -contains $fileExt
}

function Get-RelativePath {
    param([string]$FullPath, [string]$BasePath)
    return $FullPath.Substring($BasePath.Length).TrimStart('\', '/')
}

function Split-ContentIntoChunks {
    param(
        [string]$Content,
        [int]$ChunkSize = $CHUNK_SIZE,
        [int]$Overlap = $CHUNK_OVERLAP
    )
    
    $chunks = @()
    $contentLength = $Content.Length
    
    if ($contentLength -le $ChunkSize) {
        return @($Content)
    }
    
    $start = 0
    $chunkIndex = 0
    
    while ($start -lt $contentLength) {
        $end = [Math]::Min($start + $ChunkSize, $contentLength)
        $chunk = $Content.Substring($start, $end - $start)
        $chunks += $chunk
        
        $start = $end - $Overlap
        $chunkIndex++
        
        if ($start -ge $contentLength) { break }
    }
    
    return $chunks
}

function New-CodeDocument {
    param(
        [string]$FilePath,
        [string]$Content,
        [string]$RelativePath,
        [int]$ChunkIndex = 0,
        [int]$TotalChunks = 1
    )
    
    $fileExt = [System.IO.Path]::GetExtension($FilePath).TrimStart('.')
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    
    $doc = @{
        id = [System.Guid]::NewGuid().ToString()
        file_path = $RelativePath.Replace('\', '/')
        file_name = $fileName
        project_name = $ProjectName
        project_code = $ProjectCode
        content = $Content
        file_type = $fileExt
        chunk_index = $ChunkIndex
        total_chunks = $TotalChunks
        created_at = (Get-Date).ToString("o")
        metadata = @{
            lines_of_code = ($Content -split "`n").Count
            size_bytes = [System.Text.Encoding]::UTF8.GetByteCount($Content)
        }
    }
    
    return $doc
}

function Process-CodeFile {
    param(
        [string]$FilePath,
        [string]$BasePath,
        [ref]$ProcessedCount,
        [ref]$SkippedCount,
        [ref]$Documents
    )
    
    try {
        if (-not (Test-AllowedExtension -FilePath $FilePath)) {
            $SkippedCount.Value++
            return
        }
        
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        
        if ([string]::IsNullOrWhiteSpace($content)) {
            $SkippedCount.Value++
            return
        }
        
        $relativePath = Get-RelativePath -FullPath $FilePath -BasePath $BasePath
        
        # Split into chunks if needed
        $chunks = Split-ContentIntoChunks -Content $content
        
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            $doc = New-CodeDocument `
                -FilePath $FilePath `
                -Content $chunks[$i] `
                -RelativePath $relativePath `
                -ChunkIndex $i `
                -TotalChunks $chunks.Count
            
            $Documents.Value += $doc
        }
        
        $ProcessedCount.Value++
        
        if ($ProcessedCount.Value % 100 -eq 0) {
            Write-Log "Processed $($ProcessedCount.Value) files..." -Level "INFO"
        }
    }
    catch {
        Write-Log "Error processing file $FilePath : $_" -Level "ERROR"
        $SkippedCount.Value++
    }
}

function Extract-AndProcessZip {
    param(
        [string]$ZipFilePath,
        [string]$TempExtractPath
    )
    
    Write-Log "Extracting ZIP file: $ZipFilePath" -Level "INFO"
    
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFilePath, $TempExtractPath)
        Write-Log "Extraction completed" -Level "SUCCESS"
    }
    catch {
        Write-Log "Failed to extract ZIP: $_" -Level "ERROR"
        throw
    }
    
    $documents = @()
    $processedCount = 0
    $skippedCount = 0
    
    Write-Log "Processing code files..." -Level "INFO"
    
    $allFiles = Get-ChildItem -Path $TempExtractPath -Recurse -File
    
    foreach ($file in $allFiles) {
        Process-CodeFile `
            -FilePath $file.FullName `
            -BasePath $TempExtractPath `
            -ProcessedCount ([ref]$processedCount) `
            -SkippedCount ([ref]$skippedCount) `
            -Documents ([ref]$documents)
    }
    
    Write-Log "Processed: $processedCount files, Skipped: $skippedCount files" -Level "SUCCESS"
    
    return $documents
}

# Main execution
try {
    Write-Log "Starting code corpus preparation" -Level "INFO"
    Write-Log "Project: $ProjectName ($ProjectCode)" -Level "INFO"
    
    # Validate input
    if (-not (Test-Path $ZipPath)) {
        throw "ZIP file not found: $ZipPath"
    }
    
    # Create output directory
    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Log "Created output directory: $OutputPath" -Level "SUCCESS"
    }
    
    # Create temporary extraction directory
    $tempDir = Join-Path $env:TEMP "code_corpus_temp_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    
    try {
        # Process the ZIP file
        $documents = Extract-AndProcessZip -ZipFilePath $ZipPath -TempExtractPath $tempDir
        
        Write-Log "Total documents created: $($documents.Count)" -Level "INFO"
        
        # Save documents as JSON files
        Write-Log "Saving documents to output directory..." -Level "INFO"
        
        $batchSize = 1000
        $batchNumber = 0
        
        for ($i = 0; $i -lt $documents.Count; $i += $batchSize) {
            $batch = $documents[$i..[Math]::Min($i + $batchSize - 1, $documents.Count - 1)]
            $outputFile = Join-Path $OutputPath "${ProjectCode}_code_batch_${batchNumber}.json"
            
            $batch | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Encoding UTF8
            Write-Log "Saved batch $batchNumber to: $outputFile" -Level "SUCCESS"
            
            $batchNumber++
        }
        
        # Create summary file
        $summary = @{
            project_name = $ProjectName
            project_code = $ProjectCode
            total_documents = $documents.Count
            total_batches = $batchNumber
            created_at = (Get-Date).ToString("o")
            source_zip = $ZipPath
            allowed_extensions = $AllowedExtensions -split ","
        }
        
        $summaryFile = Join-Path $OutputPath "${ProjectCode}_summary.json"
        $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryFile -Encoding UTF8
        
        Write-Log "✅ Code corpus preparation completed successfully!" -Level "SUCCESS"
        Write-Log "Output directory: $OutputPath" -Level "INFO"
        Write-Log "Total documents: $($documents.Count)" -Level "INFO"
        Write-Log "Total batches: $batchNumber" -Level "INFO"
    }
    finally {
        # Cleanup temporary directory
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force
            Write-Log "Cleaned up temporary files" -Level "INFO"
        }
    }
}
catch {
    Write-Log "❌ Failed to prepare code corpus: $_" -Level "ERROR"
    exit 1
}