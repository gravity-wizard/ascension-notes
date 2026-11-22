<?php
declare(strict_types=1);

require_once __DIR__ . '/lib/bootstrap.php';
$config = tw23_load_config(__DIR__);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, private');
header('CDN-Cache-Control: no-store');
header('Cloudflare-CDN-Cache-Control: no-store');

function json_out(int $code, array $payload): never {
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    exit;
}

function read_json_body(): array {
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') return [];
    $decoded = json_decode($raw, true);
    return is_array($decoded) ? $decoded : [];
}

function is_https(): bool {
    if (!empty($_SERVER['HTTP_X_FORWARDED_PROTO'])) {
        return str_starts_with((string)$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https');
    }
    return !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
}

function base_url_prefix(): string {
    $proto = is_https() ? 'https' : 'http';
    $host = $_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? 'twisted23.com';
    $scriptDir = str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? ''));
    $basePath = ($scriptDir === '/' || $scriptDir === '.') ? '' : rtrim($scriptDir, '/');
    return "{$proto}://{$host}{$basePath}";
}

function client_ip(): string {
    return (string)($_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1');
}

function default_state(): array {
    return [
        'imagesBySlug' => [],
        'dailyUploadsByUserDay' => [],
    ];
}

function with_store(array $config, callable $fn): mixed {
    $dir = rtrim($config['data_dir'], '/');
    if (!is_dir($dir)) mkdir($dir, 0755, true);
    $file = $dir . '/twisted23-store.json';
    $fp = fopen($file, 'c+');
    if (!$fp) throw new RuntimeException('Cannot open data store');
    flock($fp, LOCK_EX);
    try {
        $raw = stream_get_contents($fp);
        $state = $raw ? (json_decode($raw, true) ?: default_state()) : default_state();
        $state = array_merge(default_state(), $state);
        $mutate = false;
        $result = $fn($state, $mutate);
        if ($mutate) {
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, json_encode($state, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
            fflush($fp);
        }
        return $result;
    } finally {
        flock($fp, LOCK_UN);
        fclose($fp);
    }
}

function detect_image_format(string $bytes): ?array {
    if (strlen($bytes) < 12) return null;
    if (substr($bytes, 0, 4) === "\x89PNG") return ['ext' => 'png', 'mime' => 'image/png'];
    if (substr($bytes, 0, 3) === "\xff\xd8\xff") return ['ext' => 'jpg', 'mime' => 'image/jpeg'];
    if (substr($bytes, 0, 4) === 'RIFF' && substr($bytes, 8, 4) === 'WEBP') return ['ext' => 'webp', 'mime' => 'image/webp'];
    if (substr($bytes, 0, 3) === 'GIF') return ['ext' => 'gif', 'mime' => 'image/gif'];
    return null;
}

function sanitize_slug(string $raw): string {
    $s = strtolower(trim($raw));
    $s = str_replace(["'", "’"], '', $s);
    $s = preg_replace('/[^a-z0-9]+/', '-', $s) ?? '';
    return substr(trim($s, '-'), 0, 48);
}

function random_short_code(int $len = 4): string {
    $alpha = '0123456789abcdefghijklmnopqrstuvwxyz';
    $out = '';
    $bytes = random_bytes($len);
    for ($i = 0; $i < $len; $i++) {
        $out .= $alpha[ord($bytes[$i]) % 36];
    }
    return $out;
}

function pick_unique_slug(string $customName, array $existing): string {
    $req = sanitize_slug($customName);
    if ($req !== '') {
        if (!isset($existing[$req])) return $req;
        for ($i = 2; $i <= 99; $i++) {
            $cand = "{$req}-{$i}";
            if (!isset($existing[$cand])) return $cand;
        }
        return $req . '-' . random_short_code(3);
    }
    for ($len = 4; $len <= 6; $len++) {
        for ($a = 0; $a < 24; $a++) {
            $cand = random_short_code($len);
            if (!isset($existing[$cand])) return $cand;
        }
    }
    return random_short_code(7);
}

function build_snippets(string $root, array $rec): array {
    $direct = "{$root}/i/" . rawurlencode($rec['storedFilename']);
    $viewer = "{$root}/?img=" . rawurlencode($rec['slug']);
    $alt = str_replace(['"', '<', '>'], '', ($rec['title'] ?? $rec['slug']));
    return [
        'directUrl' => $direct,
        'viewerUrl' => $viewer,
        'html' => "<img src=\"{$direct}\" alt=\"{$alt}\" />",
        'htmlLinked' => "<a href=\"{$viewer}\"><img src=\"{$direct}\" alt=\"{$alt}\" /></a>",
        'bbcode' => "[img]{$direct}[/img]",
        'bbcodeLinked' => "[url={$viewer}][img]{$direct}[/img][/url]",
        'markdown' => "![{$alt}]({$direct})",
        'markdownLinked' => "[![{$alt}]({$direct})]({$viewer})",
        'bytes' => $rec['bytes'],
    ];
}

$route = trim((string)($_GET['route'] ?? ''), '/');
if ($route === '' && isset($_SERVER['REQUEST_URI'])) {
    $p = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '';
    if (($pos = strpos($p, '/api/')) !== false) {
        $route = trim(substr($p, $pos + 5), '/');
    }
}
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($route === 'health') {
    json_out(200, [
        'ok' => true,
        'brand' => 'Twisted23',
        'runtime' => 'hostinger-php',
        'maxImageBytes' => (int)$config['max_image_bytes'],
    ]);
}

if ($route === 'images/upload' && $method === 'POST') {
    $b = read_json_body();
    $rawData = (string)($b['dataBase64'] ?? $b['dataUrl'] ?? '');
    if ($rawData === '') json_out(400, ['ok' => false, 'error' => 'Choose an image file to upload.']);
    $b64 = str_contains($rawData, ',') ? explode(',', $rawData, 2)[1] : $rawData;
    $bytes = base64_decode($b64, true);
    if ($bytes === false) json_out(400, ['ok' => false, 'error' => 'Invalid image data.']);

    $fmt = detect_image_format($bytes);
    if (!$fmt) json_out(400, ['ok' => false, 'error' => 'Only PNG, JPEG, WebP, and GIF images are supported.']);
    $maxBytes = (int)$config['max_image_bytes'];
    if (strlen($bytes) > $maxBytes) {
        json_out(413, ['ok' => false, 'error' => 'Image exceeds ' . round($maxBytes / 1024) . ' KB limit.']);
    }

    $dailyQuota = (int)(getenv('TWISTED23_IP_DAILY_QUOTA') ?: 60);
    $ipHash = substr(hash('sha256', client_ip()), 0, 12);
    $dayKey = 'ip:' . $ipHash . ':' . gmdate('Y-m-d');
    $rootUrl = base_url_prefix();

    $res = with_store($config, function (array &$state, bool &$mutate) use ($config, $b, $bytes, $fmt, $maxBytes, $dailyQuota, $dayKey, $rootUrl): array {
        $used = (int)($state['dailyUploadsByUserDay'][$dayKey] ?? 0);
        if ($used >= $dailyQuota) {
            return ['status' => 429, 'body' => ['ok' => false, 'error' => 'Daily upload limit reached. Try again tomorrow.']];
        }

        $customName = (string)($b['customName'] ?? $b['subject'] ?? '');
        $slug = pick_unique_slug($customName, $state['imagesBySlug']);
        $storedName = "{$slug}.{$fmt['ext']}";
        $uploadsDir = rtrim($config['data_dir'], '/') . '/uploads';
        if (!is_dir($uploadsDir)) mkdir($uploadsDir, 0755, true);
        file_put_contents($uploadsDir . '/' . $storedName, $bytes);

        $title = substr(trim($customName), 0, 64) ?: $slug;
        $rec = [
            'slug' => $slug,
            'storedFilename' => $storedName,
            'ext' => $fmt['ext'],
            'mime' => $fmt['mime'],
            'bytes' => strlen($bytes),
            'etag' => '"' . substr(hash('sha256', $bytes), 0, 16) . '"',
            'title' => $title,
            'createdAtIso' => gmdate('c'),
        ];
        $rec['snippets'] = build_snippets($rootUrl, $rec);
        $state['imagesBySlug'][$slug] = $rec;
        $state['dailyUploadsByUserDay'][$dayKey] = $used + 1;
        $mutate = true;

        return [
            'status' => 200,
            'body' => [
                'ok' => true,
                'image' => $rec,
                'hosting' => [
                    'maxImageBytes' => $maxBytes,
                    'dailyQuota' => $dailyQuota,
                    'dailyRemaining' => max(0, $dailyQuota - ($used + 1)),
                ],
            ],
        ];
    });
    json_out($res['status'], $res['body']);
}

if (str_starts_with($route, 'images/')) {
    $slug = preg_replace('/[^0-9a-z-]/', '', substr($route, 7));
    $rec = with_store($config, fn(array $state) => $state['imagesBySlug'][$slug] ?? null);
    if (!$rec) json_out(404, ['ok' => false, 'error' => 'Image not found']);
    $rec['snippets'] = build_snippets(base_url_prefix(), $rec);
    json_out(200, ['ok' => true, 'image' => $rec]);
}

json_out(404, ['ok' => false, 'error' => "Unknown API route: {$route}"]);
