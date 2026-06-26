import typography from "@tailwindcss/typography";

/** @type {import('tailwindcss').Config} */
export default {
  content: ["./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}"],
  theme: {
    extend: {
      colors: {
        eagles: {
          ink: "#020403",
          night: "#070908",
          pine: "#004f43",
          green: "#009a72",
          lime: "#dffcf2",
          gold: "#ffffff",
          line: "#d6e3dc",
          mist: "#f4fbf7",
          white: "#ffffff"
        }
      },
      boxShadow: {
        "match-card": "0 18px 50px rgba(2, 4, 3, 0.14)"
      },
      fontFamily: {
        sans: [
          "Inter",
          "ui-sans-serif",
          "system-ui",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "sans-serif"
        ],
        display: [
          "Oswald",
          "Arial Narrow",
          "ui-sans-serif",
          "system-ui",
          "sans-serif"
        ]
      }
    }
  },
  plugins: [typography]
};
