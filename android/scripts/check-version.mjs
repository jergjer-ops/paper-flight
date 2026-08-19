import fs from 'node:fs';

const packageVersion = JSON.parse(fs.readFileSync('package.json', 'utf8')).version;
const gradle = fs.readFileSync('android/app/build.gradle', 'utf8');
const config = fs.readFileSync('www/public-config.js', 'utf8');
const privacy = fs.readFileSync('www/privacy.html', 'utf8');
const gradleVersion = gradle.match(/versionName\s+"([^"]+)"/)?.[1];
const configVersion = config.match(/appVersion:\s*"([^"]+)"/)?.[1];

const versions = { packageVersion, gradleVersion, configVersion };
if (new Set(Object.values(versions)).size !== 1) {
  console.error('VERSION MISMATCH', versions);
  process.exit(1);
}
if (!privacy.includes(`Версия приложения:</strong> ${packageVersion}`)) {
  console.error(`PRIVACY VERSION MISMATCH: expected ${packageVersion}`);
  process.exit(1);
}
console.log(`VERSION CHECK PASSED: ${packageVersion}`);
