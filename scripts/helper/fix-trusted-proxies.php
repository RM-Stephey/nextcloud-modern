<?php
/**
 * Fix Nextcloud Trusted Proxies Configuration
 * This script directly modifies the config.php to set trusted_proxies as an array
 */

// Path to Nextcloud config
$configFile = '/var/www/html/config/config.php';

// Load existing config
if (!file_exists($configFile)) {
    die("Error: Config file not found at $configFile\n");
}

require_once $configFile;

if (!isset($CONFIG) || !is_array($CONFIG)) {
    die("Error: Invalid config file format\n");
}

// Define trusted proxy ranges
// Including Docker networks, Tailscale network, and Cloudflare IPs
$trustedProxies = [
    '10.0.0.0/8',          // Private network
    '172.16.0.0/12',       // Docker default
    '192.168.0.0/16',      // Private network
    '100.64.0.0/10',       // Tailscale CGNAT range
    'fd7a:115c:a1e0::/48', // Tailscale IPv6
    '173.245.48.0/20',     // Cloudflare
    '103.21.244.0/22',     // Cloudflare
    '103.22.200.0/22',     // Cloudflare
    '103.31.4.0/22',       // Cloudflare
    '141.101.64.0/18',     // Cloudflare
    '108.162.192.0/18',    // Cloudflare
    '190.93.240.0/20',     // Cloudflare
    '188.114.96.0/20',     // Cloudflare
    '197.234.240.0/22',    // Cloudflare
    '198.41.128.0/17',     // Cloudflare
    '162.158.0.0/15',      // Cloudflare
    '104.16.0.0/13',       // Cloudflare
    '104.24.0.0/14',       // Cloudflare
    '172.64.0.0/13',       // Cloudflare
    '131.0.72.0/22',       // Cloudflare
    '172.20.0.0/16',       // Your custom Docker network
];

// Update the config array
$CONFIG['trusted_proxies'] = $trustedProxies;

// Also ensure other proxy-related settings are correct
$CONFIG['overwritehost'] = 'cloud.stepheybot.dev';
$CONFIG['overwriteprotocol'] = 'https';
$CONFIG['overwritewebroot'] = '/';
$CONFIG['overwrite.cli.url'] = 'https://cloud.stepheybot.dev';

// Ensure trusted domains are set
if (!isset($CONFIG['trusted_domains'])) {
    $CONFIG['trusted_domains'] = [];
}

$trustedDomains = [
    'cloud.stepheybot.dev',
    'www.cloud.stepheybot.dev',
    'm0th3r.munchkin-ray.ts.net',
    'localhost',
];

foreach ($trustedDomains as $index => $domain) {
    $CONFIG['trusted_domains'][$index] = $domain;
}

// Set forwarded_for_headers
$CONFIG['forwarded_for_headers'] = ['HTTP_X_FORWARDED_FOR'];

// Set default phone region
$CONFIG['default_phone_region'] = 'US';

// Generate the new config file content
$configContent = "<?php\n";
$configContent .= '$CONFIG = ' . var_export($CONFIG, true) . ";\n";

// Backup the original config
$backupFile = $configFile . '.backup.' . date('Y-m-d-H-i-s');
if (!copy($configFile, $backupFile)) {
    die("Error: Failed to create backup at $backupFile\n");
}

// Write the new config
if (file_put_contents($configFile, $configContent) === false) {
    die("Error: Failed to write new config file\n");
}

echo "✓ Config file backed up to: $backupFile\n";
echo "✓ Trusted proxies configured as array with " . count($trustedProxies) . " entries\n";
echo "✓ Overwrite settings configured\n";
echo "✓ Trusted domains configured\n";
echo "\nConfiguration updated successfully!\n";
echo "\nNext steps:\n";
echo "1. Clear Nextcloud cache: docker exec -u www-data nextcloud_app php occ cache:clear\n";
echo "2. Restart containers: docker-compose restart\n";
