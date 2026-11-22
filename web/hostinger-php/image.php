<?php
declare(strict_types=1);

$config = require __DIR__ . '/config.php';

$name = ltrim((string)($_GET['name'] ?? ''), '/');
if ($name === '' && isset($_SERVER['REQUEST_URI'])) {
    $path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '';
    if (str_starts_with($path, '/i/')) {
        $name = substr($path, 3);
    }
}

if (!preg_match('/^[0-9a-z-]+\.(webp|jpg|png)$/', $name)) {
    http_response_code(400);
    exit('Invalid image filename');
}

// Optional Hostinger bandwidth hotlink guard
$allowed = $config['allowed_hotlink_hosts'] ?? [];
if (!empty($allowed) && !empty($_SERVER['HTTP_REFERER'])) {
    $refHost = strtolower((string)parse_url($_SERVER['HTTP_REFERER'], PHP_URL_HOST));
    if ($refHost !== '' && !in_array($refHost, $allowed, true)) {
        http_response_code(403);
        exit('Hotlinking disabled');
    }
}

$slug = preg_replace('/\.(webp|jpg|png)$/', '', $name);
$storeFile = rtrim($config['data_dir'], '/') . '/twisted23-store.json';
if (!is_file($storeFile)) {
    http_response_code(404);
    exit('Not found');
}

$state = json_decode((string)file_get_contents($storeFile), true) ?: [];
$rec = $state['imagesBySlug'][$slug] ?? null;
if (!$rec || ($rec['storedFilename'] ?? '') !== $name) {
    http_response_code(404);
    exit('Not found');
}

$blobPath = rtrim($config['data_dir'], '/') . '/uploads/' . basename($name);
if (!is_file($blobPath)) {
    http_response_code(404);
    exit('Blob missing');
}

$etag = $rec['etag'] ?? ('"' . md5_file($blobPath) . '"');
header('Cache-Control: public, max-age=31536000, immutable');
header('CDN-Cache-Control: public, max-age=31536000, immutable');
header('Cloudflare-CDN-Cache-Control: public, max-age=31536000, immutable');
header('ETag: ' . $etag);
header('X-Content-Type-Options: nosniff');

if (isset($_SERVER['HTTP_IF_NONE_MATCH']) && trim($_SERVER['HTTP_IF_NONE_MATCH']) === $etag) {
    http_response_code(304);
    exit;
}

header('Content-Type: ' . ($rec['mime'] ?? 'application/octet-stream'));
header('Content-Length: ' . filesize($blobPath));
readfile($blobPath);
