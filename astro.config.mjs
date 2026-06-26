import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

const site = process.env.SITE_URL || "https://greenacreeaglesfc.com.au";
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
  devToolbar: {
    enabled: false
  },
  integrations: [sitemap()],
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
