import { defineConfig } from "astro/config";
import cloudflare from "@astrojs/cloudflare";

const site = process.env.SITE_URL || "https://greenacreeaglesfc.com";
const toolbarDeps = new Set(["astro > aria-query", "astro > axobject-query"]);
const removeToolbarOptimizerDeps = () => ({
  name: "remove-astro-toolbar-optimizer-deps",
  enforce: "post",
  configResolved(config) {
    if (config.optimizeDeps?.include) {
      config.optimizeDeps.include = config.optimizeDeps.include.filter((dep) => !toolbarDeps.has(dep));
    }
  }
});

export default defineConfig({
  site,
  output: "server",
  adapter: cloudflare({
    imageService: "passthrough"
  }),
  devToolbar: {
    enabled: false
  },
  integrations: [],
  vite: {
    plugins: [removeToolbarOptimizerDeps()],
    optimizeDeps: {
      exclude: ["aria-query", "axobject-query", "astro > aria-query", "astro > axobject-query"]
    }
  },
  build: {
    format: "directory"
  }
});
