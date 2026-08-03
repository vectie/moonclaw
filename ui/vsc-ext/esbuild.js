const esbuild = require("esbuild");
const path = require("path");
const cp = require("child_process");
const fs = require("fs");

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

/**
 * @type {import('esbuild').Plugin}
 */
const esbuildProblemMatcherPlugin = {
  name: "esbuild-problem-matcher",

  setup(build) {
    build.onStart(() => {
      console.log("[watch] build started");
    });
    build.onEnd((result) => {
      result.errors.forEach(({ text, location }) => {
        console.error(`✘ [ERROR] ${text}`);
        console.error(
          `    ${location.file}:${location.line}:${location.column}:`,
        );
      });
      console.log("[watch] build finished");
    });
  },
};

function sh(command, options = {}) {
  cp.execSync(command, { stdio: "inherit", ...options });
}

function buildMoonclaw() {
  sh("moon build --target native --release", {
    cwd: path.join(__dirname, "../.."),
  });
  fs.mkdirSync(`./bin/${process.platform}`, { recursive: true });
  fs.copyFileSync(
    "../../target/native/release/build/cmd/main/main.exe",
    `./bin/${process.platform}/moonclaw`,
  );
}

async function main() {
  if (!process.env.NO_BUILD_MOONCLAW) {
    buildMoonclaw();
  }
  const ctx = await esbuild.context({
    entryPoints: ["src/extension.ts"],
    bundle: true,
    format: "cjs",
    minify: production,
    sourcemap: !production,
    sourcesContent: false,
    platform: "node",
    outfile: "dist/extension.js",
    external: ["vscode"],
    logLevel: "silent",
    plugins: [
      /* add to the end of plugins array */
      esbuildProblemMatcherPlugin,
    ],
  });
  if (watch) {
    await ctx.watch();
  } else {
    await ctx.rebuild();
    await ctx.dispose();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
