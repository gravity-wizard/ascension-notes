<?php
declare(strict_types=1);

const B38_ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyz|^';
const B38_BASE = 38;
const T0UX = 1584540571;

const DEFAULT_CLOCK_BLOCKED = [
    '666',
    'anal', 'anus', 'arse', 'bitch', 'btch', 'cock', 'c0ck', 'cunt',
    'damn', 'dick', 'd1ck', 'dyke', 'fag', 'fck', 'fuk', 'fuck',
    'hell', 'jizz', 'kike', 'klan', 'nazi', 'nig', 'n1g', 'porn',
    'p0rn', 'puss', 'rape', 'shit', 'sh1t', 'slut', 'spic', 'twat',
    'wank', 'whor', 'xxx',
];

const FALLBACK_EXACT_WORDS = [
    'sun', 'sky', 'joy', 'art', 'oak', 'dew', 'zen', 'ace', 'ray', 'gem',
    'arc', 'way', 'key', 'orb', 'day', 'era', 'leaf', 'peak', 'pine', 'wave',
    'moon', 'glow', 'hope', 'love', 'wind', 'rain', 'song', 'book', 'seed', 'star',
    'calm', 'home', 'tree', 'bird', 'gold', 'pure', 'true', 'wise', 'good', 'life',
    'angel', 'bloom', 'cloud', 'dream', 'earth', 'faith', 'grace', 'heart', 'light', 'peace',
    'beacon', 'nature', 'wonder',
];

function b38_encode(int $value): string {
    if ($value < 0) throw new InvalidArgumentException('Value must be non-negative');
    if ($value === 0) return '0';
    $out = '';
    $n = $value;
    while ($n > 0) {
        $out = B38_ALPHABET[$n % B38_BASE] . $out;
        $n = intdiv($n, B38_BASE);
    }
    return $out;
}

function b38_decode(string $raw): int {
    $s = trim($raw);
    if ($s === '') throw new InvalidArgumentException('Empty Base-38 string');
    $acc = 0;
    $len = strlen($s);
    for ($i = 0; $i < $len; $i++) {
        $idx = strpos(B38_ALPHABET, $s[$i]);
        if ($idx === false) throw new InvalidArgumentException("Invalid Base-38 char: {$s[$i]}");
        $acc = $acc * B38_BASE + $idx;
    }
    return $acc;
}

function b38_decode_expression(string $expr): int {
    $t = trim($expr);
    if (str_contains($t, '+')) {
        [$a, $b] = explode('+', $t, 2);
        return T0UX + b38_decode($a) + b38_decode($b);
    }
    if (str_contains($t, '-')) {
        [$a, $b] = explode('-', $t, 2);
        return T0UX + b38_decode($a) - b38_decode($b);
    }
    return T0UX + b38_decode($t);
}

function b38_is_lower_alnum(string $val): bool {
    return $val !== '' && preg_match('/^[0-9a-z]+$/', $val) === 1;
}

function b38_is_clean(string $val, array $blocked = DEFAULT_CLOCK_BLOCKED): bool {
    $lo = strtolower($val);
    if ($lo === '') return false;
    $leet = strtr($lo, ['0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '8' => 'b']);
    foreach ($blocked as $b) {
        if ($b !== '' && (str_contains($lo, $b) || str_contains($leet, $b))) {
            return false;
        }
    }
    return true;
}

function b38_is_clean_lower(string $val): bool {
    return b38_is_lower_alnum($val) && b38_is_clean($val);
}

function b38_sanitize_favorite(?string $raw): ?string {
    if ($raw === null || $raw === '') return null;
    $letters = substr(preg_replace('/[^a-z]/', '', strtolower($raw)), 0, 3);
    if (strlen($letters) !== 3 || !b38_is_clean_lower($letters)) return null;
    return $letters;
}

function b38_clean_exact_expression(
    ?int $unixSeconds = null,
    array $contextWords = [],
    int $maxLength = 17,
    bool $alwaysDiff = false,
    ?string $favoriteOffset = null
): array {
    $clamped = max(T0UX, $unixSeconds ?? time());
    $elapsed = $clamped - T0UX;
    $raw = b38_encode($elapsed);

    if (!$alwaysDiff && strlen($raw) <= $maxLength && b38_is_clean_lower($raw)) {
        return [
            'expression' => $raw,
            'rawClock' => $raw,
            'msd' => $raw,
            'wordUsed' => null,
            'unixSeconds' => $clamped,
        ];
    }

    $threeCtx = [];
    $otherCtx = [];
    $seen = [];

    $fav = b38_sanitize_favorite($favoriteOffset);
    if ($fav !== null) {
        $seen[$fav] = true;
        $threeCtx[] = $fav;
    }
    foreach ($contextWords as $w) {
        if (preg_match_all('/[a-z]{2,6}/', strtolower((string)$w), $m)) {
            foreach ($m[0] as $part) {
                if (isset($seen[$part]) || !b38_is_clean_lower($part)) continue;
                $seen[$part] = true;
                if (strlen($part) === 3) $threeCtx[] = $part;
                else $otherCtx[] = $part;
            }
        }
    }

    $threeFb = [];
    $otherFb = [];
    foreach (FALLBACK_EXACT_WORDS as $fb) {
        if (isset($seen[$fb]) || !b38_is_clean_lower($fb)) continue;
        $seen[$fb] = true;
        if (strlen($fb) === 3) $threeFb[] = $fb;
        else $otherFb[] = $fb;
    }

    $preferred3 = array_merge($threeCtx, $threeFb);
    $fullPool = array_merge($preferred3, $otherCtx, $otherFb);

    $maxMsd = max(0, min(3, strlen($raw) - 2));
    $msdList = [];
    for ($len = $maxMsd; $len >= 1; $len--) {
        $p = substr($raw, 0, $len);
        if (b38_is_clean_lower($p)) $msdList[] = $p;
    }
    $msdList[] = '';
    $targetLen = strlen($raw);
    $min3 = B38_BASE * B38_BASE;

    foreach ($msdList as $msd) {
        foreach ($preferred3 as $word) {
            $anch = b38_encode($elapsed + b38_decode($word));
            if (strlen($anch) === $targetLen && ($msd === '' || str_starts_with($anch, $msd)) && b38_is_clean_lower($anch)) {
                $expr = "{$anch}-{$word}";
                if (strlen($expr) <= $maxLength) {
                    return ['expression' => $expr, 'rawClock' => $raw, 'msd' => $msd, 'wordUsed' => $word, 'unixSeconds' => $clamped];
                }
            }
        }
        for ($step = $min3; $step <= $min3 + 1200; $step++) {
            $delta = b38_encode($step);
            if (strlen($delta) !== 3 || !b38_is_clean_lower($delta)) continue;
            $anch = b38_encode($elapsed + $step);
            if (strlen($anch) === $targetLen && ($msd === '' || str_starts_with($anch, $msd)) && b38_is_clean_lower($anch)) {
                $expr = "{$anch}-{$delta}";
                if (strlen($expr) <= $maxLength) {
                    return ['expression' => $expr, 'rawClock' => $raw, 'msd' => $msd, 'wordUsed' => null, 'unixSeconds' => $clamped];
                }
            }
        }
    }

    foreach ($msdList as $msd) {
        foreach ($fullPool as $word) {
            if (strlen($word) === 3) continue;
            $anch = b38_encode($elapsed + b38_decode($word));
            if (($msd === '' || str_starts_with($anch, $msd)) && b38_is_clean_lower($anch)) {
                $expr = "{$anch}-{$word}";
                if (strlen($expr) <= $maxLength) {
                    return ['expression' => $expr, 'rawClock' => $raw, 'msd' => $msd, 'wordUsed' => $word, 'unixSeconds' => $clamped];
                }
            }
        }
        for ($step = 1; $step <= 400; $step++) {
            $delta = b38_encode($step);
            if (!b38_is_clean_lower($delta)) continue;
            $anch = b38_encode($elapsed + $step);
            if (($msd === '' || str_starts_with($anch, $msd)) && b38_is_clean_lower($anch)) {
                $expr = "{$anch}-{$delta}";
                if (strlen($expr) <= $maxLength) {
                    return ['expression' => $expr, 'rawClock' => $raw, 'msd' => $msd, 'wordUsed' => null, 'unixSeconds' => $clamped];
                }
            }
        }
        foreach ($fullPool as $word) {
            $rv = b38_decode($word);
            if ($rv <= 0 || $elapsed < $rv) continue;
            $anch = b38_encode($elapsed - $rv);
            if (($msd === '' || str_starts_with($anch, $msd)) && b38_is_clean_lower($anch)) {
                $expr = "{$anch}+{$word}";
                if (strlen($expr) <= $maxLength) {
                    return ['expression' => $expr, 'rawClock' => $raw, 'msd' => $msd, 'wordUsed' => $word, 'unixSeconds' => $clamped];
                }
            }
        }
    }

    return ['expression' => $raw, 'rawClock' => $raw, 'msd' => '', 'wordUsed' => null, 'unixSeconds' => $clamped];
}
