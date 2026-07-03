<?php
// counter.php

// Path to the counter file
$counterFile = 'data/counter.txt';

// Ensure the data directory exists
if (!is_dir('data')) {
    mkdir('data', 0755, true);
}

// Ensure the counter file exists
if (!file_exists($counterFile)) {
    file_put_contents($counterFile, '0');
}

// Open the file for reading and writing
$fp = fopen($counterFile, 'c+');

if (flock($fp, LOCK_EX)) { // Acquire an exclusive lock
    // Read current count
    $count = (int)fread($fp, filesize($counterFile));
    
    // Increment count
    $count++;
    
    // Truncate file and write new count
    ftruncate($fp, 0);
    rewind($fp);
    fwrite($fp, (string)$count);
    
    // Flush and release lock
    fflush($fp);
    flock($fp, LOCK_UN);
} else {
    // Could not lock, just read the file (fallback)
    $count = (int)file_get_contents($counterFile);
}

fclose($fp);

// Return the count as JSON
header('Content-Type: application/json');
echo json_encode(['count' => $count]);
?>
