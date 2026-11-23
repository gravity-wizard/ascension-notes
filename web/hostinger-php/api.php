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
    return substr(trim($s, '-'), 0, 40);
}

function encode_compact_time(int $n): string {
    $alpha = '0123456789abcdefghijklmnopqrstuvwxyz|^';
    if ($n <= 0) return '0';
    $out = '';
    while ($n > 0) {
        $out = $alpha[$n % 38] . $out;
        $n = intdiv($n, 38);
    }
    return $out;
}

function decode_compact_time(string $s): ?int {
    $alpha = '0123456789abcdefghijklmnopqrstuvwxyz|^';
    $total = 0;
    $len = strlen($s);
    for ($i = 0; $i < $len; $i++) {
        $ch = $s[$i];
        if ($ch === '_') $ch = '0';
        elseif ($ch === '-') $ch = '^';
        $idx = strpos($alpha, $ch);
        if ($idx === false) return null;
        $total = $total * 38 + $idx;
    }
    return $total;
}

function is_clean_alnum_tag(string $s): bool {
    if ($s === '' || preg_match('/^[0-9a-z]+$/', $s) !== 1) return false;
    $leet = strtr($s, ['0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '8' => 'b']);
    $blocked = ['666', 'anal', 'anus', 'arse', 'bitch', 'btch', 'cock', 'c0ck', 'cunt', 'damn', 'dick', 'd1ck', 'dyke', 'fag', 'fck', 'fuk', 'fuck', 'hell', 'jizz', 'kike', 'klan', 'nazi', 'nig', 'n1g', 'porn', 'p0rn', 'puss', 'rape', 'shit', 'sh1t', 'slut', 'spic', 'twat', 'wank', 'whor', 'xxx'];
    foreach ($blocked as $b) {
        if (str_contains($s, $b) || str_contains($leet, $b)) return false;
    }
    return true;
}

function is_clean_acode_sequence(string $rawCode): bool {
    $joined = strtr(strtolower($rawCode), ['^' => '', '-' => '', '_' => '0']);
    $lettersOnly = preg_replace('/[0-9]/', '', $joined) ?? '';
    $digitsOnly = preg_replace('/[a-z]/', '', $joined) ?? '';
    $leetI = strtr($joined, ['0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '8' => 'b', '9' => 'g']);
    $leetL = strtr($joined, ['0' => 'o', '1' => 'l', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '8' => 'b', '9' => 'g']);
    $blocked = ['69', '666', 'anal', 'anus', 'arse', 'bitch', 'btch', 'cock', 'c0ck', 'cunt', 'damn', 'dick', 'd1ck', 'dyke', 'fag', 'fck', 'fuk', 'fuck', 'hell', 'jizz', 'kike', 'klan', 'nazi', 'nig', 'n1g', 'porn', 'p0rn', 'puss', 'rape', 'shit', 'sh1t', 'slut', 'spic', 'twat', 'wank', 'whor', 'xxx'];
    foreach ($blocked as $b) {
        if (
            str_contains($joined, $b) ||
            str_contains($lettersOnly, $b) ||
            str_contains($digitsOnly, $b) ||
            str_contains($leetI, $b) ||
            str_contains($leetL, $b)
        ) {
            return false;
        }
    }
    return true;
}

function format_msd_triad(int $msdVal): string {
    $raw = substr(str_pad(encode_compact_time($msdVal), 3, '0', STR_PAD_LEFT), -3);
    return strtr($raw, ['0' => '_', '|' => '_', '^' => '-']);
}

function a8a_from_index(int $idx): string {
    $digits = '12345789';
    $count = 5408; // 26 * 8 * 26
    $i = (($idx % $count) + $count) % $count;
    $c0 = chr(97 + intdiv($i, 208));
    $rem = $i % 208;
    $c1 = $digits[intdiv($rem, 26)];
    $c2 = chr(97 + ($rem % 26));
    return $c0 . $c1 . $c2;
}

function is_a8a_triad(string $s): bool {
    return preg_match('/^[a-z][1-57-9][a-z]$/', $s) === 1;
}

function mint_acode_time_slug(int $unixSeconds, array $existing): array {
    $epoch = 1584540571;
    $triadBase = 54872; // 38^3
    $a8aCount = 5408;
    $sec = max($epoch, $unixSeconds);
    $elapsed = $sec - $epoch;
    $msdVal = intdiv($elapsed, $triadBase);
    $lsdVal = $elapsed % $triadBase;
    $msd = format_msd_triad($msdVal);

    $directLsd = encode_compact_time($lsdVal);
    if (strlen($directLsd) === 3 && is_a8a_triad($directLsd)) {
        $canonical = "{$msd}^{$directLsd}";
        $slug = "{$msd}-{$directLsd}";
        if (is_clean_acode_sequence($canonical) && !isset($existing[$slug]) && !isset($existing[$canonical])) {
            return ['slug' => $slug, 'canonical' => $canonical];
        }
    }

    for ($attempt = 0; $attempt < 5000; $attempt++) {
        $h1 = ((($elapsed ^ 0x9e3779b9) * 2654435761) ^ (($attempt + 1) * 2246822519)) & 0x7fffffff;
        $h2 = ((($elapsed ^ 0x85ebca6b) * 3266489917) ^ (($attempt + 1) * 668265263)) & 0x7fffffff;
        $t1 = a8a_from_index($h1 % $a8aCount);
        $t2 = a8a_from_index($h2 % $a8aCount);
        if (!is_clean_acode_sequence($t1) || !is_clean_acode_sequence($t2)) continue;

        $v1 = decode_compact_time($t1) ?? 0;
        $v2 = decode_compact_time($t2) ?? 0;
        $needed = ((($lsdVal - $msdVal - $v1 - $v2) % $triadBase) + $triadBase) % $triadBase;
        $t3 = encode_compact_time($needed);
        if (strlen($t3) !== 3 || !is_a8a_triad($t3)) continue;

        $canonical = "{$msd}^{$t1}^{$t2}^{$t3}";
        $slug = "{$msd}-{$t1}-{$t2}-{$t3}";
        if (!is_clean_acode_sequence($canonical)) continue;
        if (!isset($existing[$slug]) && !isset($existing[$canonical])) {
            return ['slug' => $slug, 'canonical' => $canonical];
        }
    }

    $fallback = "{$msd}-a1a-a1a-a1a";
    return ['slug' => $fallback, 'canonical' => str_replace('-', '^', $fallback)];
}

function pick_unique_slug(string $customName, array $existing): array {
    $prefix = sanitize_slug($customName);
    if ($prefix === '') {
        return mint_acode_time_slug(time(), $existing);
    }
    $epoch = 1584540571;
    $agyOffset = 10 * 38 * 38 + 16 * 38 + 34; // decode("agy")
    $baseSec = max($epoch, time());
    for ($bump = 0; $bump < 90; $bump++) {
        $elapsed = ($baseSec + $bump) - $epoch;
        $anchor = encode_compact_time($elapsed + $agyOffset);
        if (!is_clean_alnum_tag($anchor) || !is_clean_acode_sequence($anchor)) continue;
        $cand = "{$prefix}-{$anchor}-agy";
        if (!is_clean_acode_sequence($cand)) continue;
        if (!isset($existing[$cand])) return ['slug' => $cand, 'canonical' => null];
    }
    $fb = preg_replace('/[^0-9a-z]/', 'x', encode_compact_time($baseSec - $epoch + $agyOffset)) . '-agy';
    return ['slug' => "{$prefix}-{$fb}", 'canonical' => null];
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
    $ctype = strtolower((string)($_SERVER['CONTENT_TYPE'] ?? ''));
    $bytes = '';
    $customName = '';

    if (isset($_FILES['file']) && is_uploaded_file($_FILES['file']['tmp_name'])) {
        $bytes = (string)file_get_contents($_FILES['file']['tmp_name']);
        $customName = (string)($_POST['customName'] ?? $_POST['subject'] ?? '');
    } elseif (str_starts_with($ctype, 'application/octet-stream')) {
        $bytes = (string)file_get_contents('php://input');
        $customName = rawurldecode((string)($_SERVER['HTTP_X_CUSTOM_NAME'] ?? ''));
    } else {
        $b = read_json_body();
        $rawData = (string)($b['dataBase64'] ?? $b['dataUrl'] ?? '');
        if ($rawData === '') json_out(400, ['ok' => false, 'error' => 'Choose an image file to upload.']);
        $b64 = str_contains($rawData, ',') ? explode(',', $rawData, 2)[1] : $rawData;
        $decoded = base64_decode($b64, true);
        if ($decoded === false) json_out(400, ['ok' => false, 'error' => 'Invalid image data.']);
        $bytes = $decoded;
        $customName = (string)($b['customName'] ?? $b['subject'] ?? '');
    }

    if ($bytes === '') json_out(400, ['ok' => false, 'error' => 'Empty image payload.']);
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

    $res = with_store($config, function (array &$state, bool &$mutate) use ($config, $customName, $bytes, $fmt, $maxBytes, $dailyQuota, $dayKey, $rootUrl): array {
        $used = (int)($state['dailyUploadsByUserDay'][$dayKey] ?? 0);
        if ($used >= $dailyQuota) {
            return ['status' => 429, 'body' => ['ok' => false, 'error' => 'Daily upload limit reached. Try again tomorrow.']];
        }

        $minted = pick_unique_slug($customName, $state['imagesBySlug']);
        $slug = $minted['slug'];
        $storedName = "{$slug}.{$fmt['ext']}";
        $uploadsDir = rtrim($config['data_dir'], '/') . '/uploads';
        if (!is_dir($uploadsDir)) mkdir($uploadsDir, 0755, true);
        file_put_contents($uploadsDir . '/' . $storedName, $bytes);

        $title = substr(trim($customName), 0, 64) ?: ($minted['canonical'] ?? $slug);
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
    $slug = str_replace('^', '-', preg_replace('/[^0-9a-z_^-]/', '', substr($route, 7)) ?? '');
    $rec = with_store($config, fn(array $state) => $state['imagesBySlug'][$slug] ?? null);
    if (!$rec) json_out(404, ['ok' => false, 'error' => 'Image not found']);
    $rec['snippets'] = build_snippets(base_url_prefix(), $rec);
    json_out(200, ['ok' => true, 'image' => $rec]);
}

json_out(404, ['ok' => false, 'error' => "Unknown API route: {$route}"]);
