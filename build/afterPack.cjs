const { execFileSync } = require("node:child_process");
const path = require("node:path");

// electron-builder injects placeholder usage strings for hardware this app
// never touches. A stray camera prompt reason is misleading, so strip them.
const UNUSED_KEYS = [
  "NSCameraUsageDescription",
  "NSBluetoothAlwaysUsageDescription",
  "NSBluetoothPeripheralUsageDescription",
];

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== "darwin") return;

  const plist = path.join(
    context.appOutDir,
    `${context.packager.appInfo.productFilename}.app`,
    "Contents",
    "Info.plist",
  );

  for (const key of UNUSED_KEYS) {
    try {
      execFileSync("/usr/bin/plutil", ["-remove", key, plist]);
    } catch {
      // Key was not there. Nothing to do.
    }
  }
};
