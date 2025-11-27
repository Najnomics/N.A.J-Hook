const fs = require("fs");
const path = require("path");

const TARGET_FILE = path.resolve(
  __dirname,
  "..",
  "node_modules",
  "cofhe-foundry-mocks",
  "src",
  "MockQueryDecrypter.sol"
);

const SEARCH = "function testQueryDecrypt";
const REPLACEMENT = "function internalQueryDecrypt";

try {
  if (fs.existsSync(TARGET_FILE)) {
    const source = fs.readFileSync(TARGET_FILE, "utf8");
    if (source.includes(SEARCH)) {
      const patched = source.replaceAll(SEARCH, REPLACEMENT);
      fs.writeFileSync(TARGET_FILE, patched, "utf8");
      console.log("[postinstall] Patched MockQueryDecrypter.sol to disable forge auto-tests");
    } else {
      console.log("[postinstall] MockQueryDecrypter.sol already patched");
    }
  } else {
    console.warn("[postinstall] MockQueryDecrypter.sol not found, skipping patch");
  }
} catch (err) {
  console.warn("[postinstall] Failed to patch MockQueryDecrypter.sol:", err.message);
}

