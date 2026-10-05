(() => {
  const script = document.createElement("script");
  // Load TinyMCE webcomponent from local test-app assets to keep TinyMCE tests offline-stable
  script.src = "/lib/tinymce-webcomponent.js";
  script.defer = true;
  document.head.appendChild(script);
})();
