<?php
declare(strict_types=1);

$config = require __DIR__ . '/config.php';
require_once __DIR__ . '/lib/base38.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

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

function req_origin(): string {
    $proto = is_https() ? 'https' : 'http';
    $host = $_SERVER['HTTP_X_FORWARDED_HOST'] ?? $_SERVER['HTTP_HOST'] ?? 'twisted23.com';
    return "{$proto}://{$host}";
}

function b64url_encode(string $data): string {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function b64url_decode(string $data): string {
    $pad = strlen($data) % 4;
    if ($pad > 0) $data .= str_repeat('=', 4 - $pad);
    return base64_decode(strtr($data, '-_', '+/')) ?: '';
}

function sign_session(array $payload, string $secret, int $ttl = 1209600): string {
    $payload['exp'] = time() + $ttl;
    $enc = b64url_encode((string)json_encode($payload));
    $sig = b64url_encode(hash_hmac('sha256', $enc, $secret, true));
    return "{$enc}.{$sig}";
}

function verify_session(?string $token, string $secret): ?array {
    if (!$token || !str_contains($token, '.')) return null;
    [$enc, $sig] = explode('.', $token, 2);
    $expected = b64url_encode(hash_hmac('sha256', $enc, $secret, true));
    if (!hash_equals($expected, $sig)) return null;
    $parsed = json_decode(b64url_decode($enc), true);
    if (!is_array($parsed) || ($parsed['exp'] ?? 0) < time()) return null;
    return $parsed;
}

function pwd_index(string $raw, string $secret): string {
    $norm = preg_replace('/\s+/', '', strtolower(trim($raw)));
    return hash_hmac('sha256', 'pwd:' . $norm, $secret);
}

function default_state(): array {
    return [
        'usersById' => [],
        'userIdByEmail' => [],
        'credentialByIndex' => [],
        'ndaReceipts' => [],
        'devOutbox' => [],
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

function public_user(?array $u): array {
    if (!$u) {
        return [
            'authenticated' => false,
            'tier' => 0,
            'tierLabel' => 'Level 0 · Open Link',
            'name' => 'Guest',
            'email' => null,
            'emailVerified' => false,
            'favoriteOffset' => '',
            'ndaSigned' => false,
            'ndaReceipt' => null,
        ];
    }
    return [
        'authenticated' => true,
        'id' => $u['id'],
        'tier' => (int)$u['tier'],
        'tierLabel' => ((int)$u['tier'] >= 2) ? 'Level 2 · Signed NDA' : 'Level 1 · Registered',
        'name' => $u['name'],
        'email' => $u['email'],
        'emailVerified' => !empty($u['emailVerified']),
        'favoriteOffset' => $u['favoriteOffset'] ?? '',
        'ndaSigned' => !empty($u['ndaReceipt']),
        'ndaReceipt' => !empty($u['ndaReceipt']) ? [
            'receiptId' => $u['ndaReceipt']['receiptId'],
            'signedAtIso' => $u['ndaReceipt']['signedAtIso'],
            'signedAtBase38' => $u['ndaReceipt']['signedAtBase38'],
            'receiptHash' => $u['ndaReceipt']['receiptHash'],
        ] : null,
    ];
}

function current_user(array $state, array $config): ?array {
    $claims = verify_session($_COOKIE['tw23_session'] ?? null, $config['auth_secret']);
    if (!$claims || empty($claims['userId'])) return null;
    $u = $state['usersById'][$claims['userId']] ?? null;
    if (!$u || !empty($u['revokedAt'])) return null;
    return $u;
}

function mint_tier_password(int $tier, ?string $fav, array $existingIndexes, string $secret): array {
    $favClean = b38_sanitize_favorite($fav);
    $ctx = ($tier === 2)
        ? ($favClean ? [$favClean, 'nda'] : ['nda', 'joy', 'sun'])
        : ($favClean ? [$favClean, 'sun', 'joy'] : ['sun', 'joy', 'zen']);
    $now = time();
    for ($bump = 0; $bump < 60; $bump++) {
        $res = b38_clean_exact_expression(
            $now + $bump,
            $ctx,
            17,
            true,
            ($tier === 2 && !$favClean) ? 'nda' : $favClean
        );
        $pwd = $res['expression'];
        $idx = pwd_index($pwd, $secret);
        if (!isset($existingIndexes[$idx])) {
            return [
                'password' => $pwd,
                'indexKey' => $idx,
                'hash' => password_hash($pwd, PASSWORD_DEFAULT),
                'mintedUnix' => $res['unixSeconds'],
                'suffixUsed' => $res['wordUsed'] ?? '',
            ];
        }
    }
    throw new RuntimeException('Could not mint unique Base-38 password');
}

function detect_image_format(string $bytes): ?array {
    if (strlen($bytes) < 12) return null;
    if (substr($bytes, 0, 4) === "\x89PNG") return ['ext' => 'png', 'mime' => 'image/png'];
    if (substr($bytes, 0, 3) === "\xff\xd8\xff") return ['ext' => 'jpg', 'mime' => 'image/jpeg'];
    if (substr($bytes, 0, 4) === 'RIFF' && substr($bytes, 8, 4) === 'WEBP') {
        return ['ext' => 'webp', 'mime' => 'image/webp'];
    }
    return null;
}

function build_snippets(string $origin, array $rec): array {
    $base = rtrim($origin, '/');
    $direct = "{$base}/i/" . rawurlencode($rec['storedFilename']);
    $viewer = "{$base}/?img=" . rawurlencode($rec['slug']);
    $alt = $rec['subject'] !== '' ? "{$rec['subject']} {$rec['base38Tag']}" : $rec['base38Tag'];
    $safeAlt = str_replace(['"', '<', '>'], '', $alt);
    return [
        'renameString' => "{$alt}.{$rec['ext']}",
        'directUrl' => $direct,
        'viewerUrl' => $viewer,
        'markdown' => "![{$alt}]({$direct})",
        'markdownLinked' => "[![{$alt}]({$direct})]({$viewer})",
        'htmlLinked' => "<a href=\"{$viewer}\"><img src=\"{$direct}\" alt=\"{$safeAlt}\" loading=\"lazy\" /></a>",
        'bbcode' => "[img]{$direct}[/img]",
        'bbcodeLinked' => "[url={$viewer}][img]{$direct}[/img][/url]",
        'axifMarker' => "▸[Image: {$alt}.{$rec['ext']} #{$rec['shortId']}]",
        'bytes' => $rec['bytes'],
    ];
}

function send_access_email(array $config, string $email, string $name, int $tier, string $pwd, ?string $ndaHash): string {
    $tierLabel = $tier === 2 ? 'Level 2 (Signed NDA)' : 'Level 1 (Registered)';
    $subject = "Your Twisted23.com {$tierLabel} Base-38 Access Password: {$pwd}";
    $body = "Hi {$name},\n\nYour {$tierLabel} Base-38 access password: {$pwd}\n\n"
          . "Enter it at Twisted23.com to unlock {$tierLabel}."
          . ($ndaHash ? "\nNDA SHA-256: {$ndaHash}" : '');

    if (!empty($config['resend_api_key']) && function_exists('curl_init')) {
        $ch = curl_init('https://api.resend.com/emails');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $config['resend_api_key'],
                'Content-Type: application/json',
            ],
            CURLOPT_POSTFIELDS => json_encode([
                'from' => $config['from_email'],
                'to' => [$email],
                'subject' => $subject,
                'text' => $body,
            ]),
        ]);
        $resp = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($code >= 200 && $code < 300) return 'resend';
    }
    if (!empty($config['dev_outbox'])) {
        return 'dev-outbox';
    }
    @mail($email, $subject, $body, 'From: ' . $config['from_email']);
    return 'php-mail';
}

$route = trim((string)($_GET['route'] ?? ''), '/');
if ($route === '' && isset($_SERVER['REQUEST_URI'])) {
    $p = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '';
    if (str_starts_with($p, '/api/')) $route = trim(substr($p, 5), '/');
}
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($route === 'health') {
    $now = time();
    $clk = b38_clean_exact_expression($now, ['sun'], 17, true);
    json_out(200, [
        'ok' => true,
        'brand' => 'Twisted23.com',
        'runtime' => 'hostinger-php',
        'clockBase38' => $clk['expression'],
        'unixSeconds' => $now,
        'maxImageBytes' => $config['max_image_bytes'],
        'devOutbox' => (bool)$config['dev_outbox'],
    ]);
}

if ($route === 'session') {
    $res = with_store($config, function (array &$state) use ($config): array {
        $u = current_user($state, $config);
        $today = gmdate('Y-m-d');
        $tier = $u ? (int)$u['tier'] : 0;
        $quota = $tier >= 2 ? $config['l2_daily_quota'] : ($tier === 1 ? $config['l1_daily_quota'] : 0);
        $used = $u ? (int)($state['dailyUploadsByUserDay'][$u['id'] . ':' . $today] ?? 0) : 0;
        return [
            'ok' => true,
            'user' => public_user($u),
            'devOutboxAvailable' => (bool)$config['dev_outbox'],
            'hosting' => [
                'maxImageBytes' => $config['max_image_bytes'],
                'dailyQuota' => $quota,
                'dailyUsed' => $used,
                'dailyRemaining' => max(0, $quota - $used),
            ],
        ];
    });
    json_out(200, $res);
}

if ($route === 'register' && $method === 'POST') {
    $b = read_json_body();
    $name = trim((string)($b['name'] ?? ''));
    $email = strtolower(trim((string)($b['email'] ?? '')));
    $rawFav = trim((string)($b['favoriteOffset'] ?? ''));
    if (strlen($name) < 2) json_out(400, ['ok' => false, 'error' => 'Enter your name (min 2 chars).']);
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) json_out(400, ['ok' => false, 'error' => 'Invalid email.']);
    if ($rawFav !== '' && b38_sanitize_favorite($rawFav) === null) {
        json_out(400, ['ok' => false, 'error' => 'Favorite offset must be 3 clean lowercase letters (a-z).']);
    }
    $fav = b38_sanitize_favorite($rawFav) ?? '';

    $res = with_store($config, function (array &$state, bool &$mutate) use ($config, $name, $email, $fav): array {
        $uid = $state['userIdByEmail'][$email] ?? null;
        $existing = $uid ? ($state['usersById'][$uid] ?? null) : null;
        if ($existing && !empty($existing['revokedAt'])) {
            return ['status' => 403, 'body' => ['ok' => false, 'error' => 'Access revoked.']];
        }
        $minted = mint_tier_password(1, $fav !== '' ? $fav : ($existing['favoriteOffset'] ?? null), $state['credentialByIndex'], $config['auth_secret']);
        $userId = $existing ? $existing['id'] : ('usr_' . bin2hex(random_bytes(6)));

        foreach ($state['credentialByIndex'] as $k => $cred) {
            if (($cred['userId'] ?? '') === $userId && (int)($cred['tier'] ?? 0) === 1) {
                unset($state['credentialByIndex'][$k]);
            }
        }
        $state['credentialByIndex'][$minted['indexKey']] = [
            'userId' => $userId,
            'tier' => 1,
            'hash' => $minted['hash'],
            'mintedUnix' => $minted['mintedUnix'],
            'suffixUsed' => $minted['suffixUsed'],
        ];
        $user = $existing ?: [
            'id' => $userId,
            'email' => $email,
            'name' => $name,
            'tier' => 1,
            'emailVerified' => false,
            'favoriteOffset' => $fav,
            'createdAtIso' => gmdate('c'),
            'ndaReceipt' => null,
            'revokedAt' => null,
            'issuedHistory' => [],
        ];
        $user['name'] = $name;
        if ($fav !== '') $user['favoriteOffset'] = $fav;
        $user['issuedHistory'][] = ['tier' => 1, 'issuedAtIso' => gmdate('c'), 'suffixUsed' => $minted['suffixUsed']];
        $state['usersById'][$userId] = $user;
        $state['userIdByEmail'][$email] = $userId;
        $mutate = true;
        return ['status' => 200, 'minted' => $minted, 'user' => $user];
    });

    if (($res['status'] ?? 200) !== 200) json_out($res['status'], $res['body']);
    $mode = send_access_email($config, $email, $name, 1, $res['minted']['password'], null);
    if ($mode === 'dev-outbox') {
        with_store($config, function (array &$state, bool &$mutate) use ($email, $name, $res): void {
            array_unshift($state['devOutbox'], [
                'id' => bin2hex(random_bytes(4)),
                'toEmail' => $email,
                'recipientName' => $name,
                'tier' => 1,
                'subject' => "Your Twisted23.com Level 1 Base-38 Access Password: {$res['minted']['password']}",
                'base38Password' => $res['minted']['password'],
                'sentAtIso' => gmdate('c'),
            ]);
            $state['devOutbox'] = array_slice($state['devOutbox'], 0, 30);
            $mutate = true;
        });
    }
    json_out(200, [
        'ok' => true,
        'deliveryMode' => $mode,
        'message' => "Sent your Level 1 Base-38 password to {$email}.",
    ]);
}

if ($route === 'login' && $method === 'POST') {
    $b = read_json_body();
    $pwd = preg_replace('/\s+/', '', strtolower(trim((string)($b['password'] ?? ''))));
    $emailFilter = strtolower(trim((string)($b['email'] ?? '')));
    if ($pwd === '') json_out(400, ['ok' => false, 'error' => 'Enter your Base-38 password.']);
    $idx = pwd_index($pwd, $config['auth_secret']);

    $res = with_store($config, function (array &$state, bool &$mutate) use ($idx, $pwd, $emailFilter): array {
        $cred = $state['credentialByIndex'][$idx] ?? null;
        if (!$cred || !password_verify($pwd, (string)$cred['hash'])) {
            return ['status' => 401, 'body' => ['ok' => false, 'error' => 'Invalid Base-38 password.']];
        }
        $user = $state['usersById'][$cred['userId']] ?? null;
        if (!$user || !empty($user['revokedAt'])) {
            return ['status' => 403, 'body' => ['ok' => false, 'error' => 'Account unavailable or revoked.']];
        }
        if ($emailFilter !== '' && $user['email'] !== $emailFilter) {
            return ['status' => 401, 'body' => ['ok' => false, 'error' => 'Password does not match email.']];
        }
        $user['emailVerified'] = true;
        $user['lastLoginAtIso'] = gmdate('c');
        if ((int)$cred['tier'] > (int)$user['tier']) $user['tier'] = (int)$cred['tier'];
        $state['usersById'][$user['id']] = $user;
        $mutate = true;
        return ['status' => 200, 'user' => $user];
    });
    if ($res['status'] !== 200) json_out($res['status'], $res['body']);

    $token = sign_session(['userId' => $res['user']['id'], 'tier' => $res['user']['tier']], $config['auth_secret']);
    setcookie('tw23_session', $token, [
        'expires' => time() + 1209600,
        'path' => '/',
        'httponly' => true,
        'samesite' => 'Lax',
        'secure' => is_https(),
    ]);
    json_out(200, ['ok' => true, 'user' => public_user($res['user'])]);
}

if ($route === 'logout' && $method === 'POST') {
    setcookie('tw23_session', '', ['expires' => time() - 3600, 'path' => '/', 'httponly' => true, 'samesite' => 'Lax']);
    json_out(200, ['ok' => true, 'user' => public_user(null)]);
}

if ($route === 'preferences' && $method === 'POST') {
    $b = read_json_body();
    $rawFav = trim((string)($b['favoriteOffset'] ?? ''));
    $fav = $rawFav !== '' ? b38_sanitize_favorite($rawFav) : '';
    if ($rawFav !== '' && $fav === null) {
        json_out(400, ['ok' => false, 'error' => 'Favorite offset must be 3 clean lowercase letters (a-z).']);
    }
    $res = with_store($config, function (array &$state, bool &$mutate) use ($config, $fav): array {
        $u = current_user($state, $config);
        if (!$u || (int)$u['tier'] < 1) return ['status' => 401, 'body' => ['ok' => false, 'error' => 'Unauthorized']];
        $u['favoriteOffset'] = $fav ?? '';
        $state['usersById'][$u['id']] = $u;
        $mutate = true;
        return ['status' => 200, 'body' => ['ok' => true, 'user' => public_user($u)]];
    });
    json_out($res['status'], $res['body']);
}

if ($route === 'nda') {
    $md = (string)file_get_contents($config['nda_template']);
    $sha = hash('sha256', $md);
    $u = with_store($config, fn(array $state) => current_user($state, $config));
    json_out(200, ['ok' => true, 'markdown' => $md, 'templateSha256' => $sha, 'user' => public_user($u)]);
}

if ($route === 'nda/sign' && $method === 'POST') {
    $b = read_json_body();
    if (empty($b['agreed'])) json_out(400, ['ok' => false, 'error' => 'Check the agreement box.']);
    $legal = trim((string)($b['legalName'] ?? ''));
    $sig = trim((string)($b['typedSignature'] ?? ''));
    if (strlen($legal) < 2 || strlen($sig) < 2) json_out(400, ['ok' => false, 'error' => 'Enter legal name & signature.']);

    $md = (string)file_get_contents($config['nda_template']);
    $tplSha = hash('sha256', $md);
    $now = time();
    $b38Tag = b38_clean_exact_expression($now, ['nda'], 17, true, 'nda')['expression'];

    $res = with_store($config, function (array &$state, bool &$mutate) use ($config, $legal, $sig, $b, $tplSha, $now, $b38Tag): array {
        $u = current_user($state, $config);
        if (!$u || (int)$u['tier'] < 1 || empty($u['emailVerified'])) {
            return ['status' => 401, 'body' => ['ok' => false, 'error' => 'Verify Level 1 first.']];
        }
        $receipt = [
            'receiptId' => 'NDA-' . strtoupper($b38Tag),
            'userId' => $u['id'],
            'email' => $u['email'],
            'legalName' => $legal,
            'typedSignature' => $sig,
            'companyOrRole' => trim((string)($b['companyOrRole'] ?? '')),
            'signedAtIso' => gmdate('c', $now),
            'signedAtBase38' => $b38Tag,
            'signedAtUnix' => $now,
            'templateSha256' => $tplSha,
            'clientIp' => $_SERVER['REMOTE_ADDR'] ?? '127.0.0.1',
            'userAgent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown',
        ];
        $receipt['receiptHash'] = hash('sha256', (string)json_encode($receipt));
        $minted = mint_tier_password(2, $u['favoriteOffset'] ?? null, $state['credentialByIndex'], $config['auth_secret']);
        foreach ($state['credentialByIndex'] as $k => $cred) {
            if (($cred['userId'] ?? '') === $u['id'] && (int)($cred['tier'] ?? 0) === 2) {
                unset($state['credentialByIndex'][$k]);
            }
        }
        $state['credentialByIndex'][$minted['indexKey']] = [
            'userId' => $u['id'],
            'tier' => 2,
            'hash' => $minted['hash'],
            'mintedUnix' => $minted['mintedUnix'],
            'suffixUsed' => $minted['suffixUsed'],
        ];
        $u['tier'] = 2;
        $u['ndaReceipt'] = $receipt;
        $state['usersById'][$u['id']] = $u;
        array_unshift($state['ndaReceipts'], $receipt);
        $mutate = true;
        return ['status' => 200, 'user' => $u, 'receipt' => $receipt, 'l2Pwd' => $minted['password']];
    });
    if ($res['status'] !== 200) json_out($res['status'], $res['body']);

    $mode = send_access_email($config, $res['user']['email'], $res['user']['name'], 2, $res['l2Pwd'], $res['receipt']['receiptHash']);
    $token = sign_session(['userId' => $res['user']['id'], 'tier' => 2], $config['auth_secret']);
    setcookie('tw23_session', $token, ['expires' => time() + 1209600, 'path' => '/', 'httponly' => true, 'samesite' => 'Lax', 'secure' => is_https()]);
    json_out(200, [
        'ok' => true,
        'user' => public_user($res['user']),
        'level2Password' => $res['l2Pwd'],
        'ndaReceipt' => $res['receipt'],
        'deliveryMode' => $mode,
    ]);
}

if ($route === 'images/upload' && $method === 'POST') {
    $b = read_json_body();
    $rawData = (string)($b['dataBase64'] ?? $b['dataUrl'] ?? '');
    if ($rawData === '') json_out(400, ['ok' => false, 'error' => 'Missing image data.']);
    $b64 = str_contains($rawData, ',') ? explode(',', $rawData, 2)[1] : $rawData;
    $bytes = base64_decode($b64, true);
    if ($bytes === false) json_out(400, ['ok' => false, 'error' => 'Invalid base64 image.']);

    $fmt = detect_image_format($bytes);
    if (!$fmt) json_out(400, ['ok' => false, 'error' => 'Only PNG, JPEG, and WebP allowed.']);
    $maxBytes = (int)$config['max_image_bytes'];
    if (strlen($bytes) > $maxBytes) {
        json_out(413, ['ok' => false, 'error' => 'Image exceeds Hostinger per-image byte budget.']);
    }

    $res = with_store($config, function (array &$state, bool &$mutate) use ($config, $b, $bytes, $fmt, $maxBytes): array {
        $u = current_user($state, $config);
        if (!$u || (int)$u['tier'] < 1 || empty($u['emailVerified'])) {
            return ['status' => 401, 'body' => ['ok' => false, 'error' => 'Level 1 verification required.']];
        }
        $today = gmdate('Y-m-d');
        $quota = ((int)$u['tier'] >= 2) ? $config['l2_daily_quota'] : $config['l1_daily_quota'];
        $dayKey = $u['id'] . ':' . $today;
        $used = (int)($state['dailyUploadsByUserDay'][$dayKey] ?? 0);
        if ($used >= $quota) {
            return ['status' => 429, 'body' => ['ok' => false, 'error' => 'Daily upload quota reached.']];
        }

        $subject = substr(trim((string)($b['subject'] ?? '')), 0, 64);
        $words = $subject !== '' ? (preg_split('/[^a-zA-Z0-9]+/', $subject, -1, PREG_SPLIT_NO_EMPTY) ?: []) : [];
        $fav = $b['favoriteOffset'] ?? ($u['favoriteOffset'] ?? null);
        $clk = b38_clean_exact_expression((int)($b['unixSeconds'] ?? time()), $words, 17, true, $fav);

        $shortId = substr(hash('sha256', $bytes), 0, 4);
        $slug = preg_replace('/[^0-9a-z-]/', '', $clk['expression'] . '-' . $shortId);
        $storedName = "{$slug}.{$fmt['ext']}";
        $uploadsDir = rtrim($config['data_dir'], '/') . '/uploads';
        if (!is_dir($uploadsDir)) mkdir($uploadsDir, 0755, true);
        file_put_contents($uploadsDir . '/' . $storedName, $bytes);

        $rec = [
            'slug' => $slug,
            'storedFilename' => $storedName,
            'ext' => $fmt['ext'],
            'mime' => $fmt['mime'],
            'bytes' => strlen($bytes),
            'etag' => '"' . substr(hash('sha256', $bytes), 0, 16) . '"',
            'shortId' => $shortId,
            'subject' => $subject,
            'base38Tag' => $clk['expression'],
            'unixSeconds' => $clk['unixSeconds'],
            'uploaderId' => $u['id'],
            'uploaderTier' => (int)$u['tier'],
            'createdAtIso' => gmdate('c'),
        ];
        $rec['snippets'] = build_snippets(req_origin(), $rec);
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
                    'dailyQuota' => $quota,
                    'dailyUsed' => $used + 1,
                    'dailyRemaining' => max(0, $quota - ($used + 1)),
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
    $rec['snippets'] = build_snippets(req_origin(), $rec);
    json_out(200, ['ok' => true, 'image' => $rec]);
}

if ($route === 'dev-outbox') {
    if (empty($config['dev_outbox'])) json_out(404, ['ok' => false, 'error' => 'Not found']);
    $emailFilter = strtolower(trim((string)($_GET['email'] ?? '')));
    $msgs = with_store($config, function (array $state) use ($emailFilter): array {
        $list = $state['devOutbox'] ?? [];
        if ($emailFilter !== '') {
            $list = array_values(array_filter($list, fn($m) => ($m['toEmail'] ?? '') === $emailFilter));
        }
        return $list;
    });
    json_out(200, ['ok' => true, 'messages' => $msgs]);
}

json_out(404, ['ok' => false, 'error' => "Unknown API route: {$route}"]);
