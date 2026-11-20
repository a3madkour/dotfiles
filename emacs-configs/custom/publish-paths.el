;;; publish-paths.el --- tangled from config.org, "Publishing paths"; edit it there  -*- lexical-binding: t; -*-
(setq a3madkour-pub/site-data-dir
      (expand-file-name "~/Sync/Workspace/a3madkour.github.io/data/")
      a3madkour-pub/org-notes-dir (expand-file-name "~/org/notes/")
      a3madkour-pub/essays-dir (expand-file-name "~/org/essays/")
      a3madkour-pub/poetry-dir
      (expand-file-name "~/org/Artistic/creative-writing/poetry/")
      a3madkour-pub-canonical-asset-root (expand-file-name "~/org/notes/assets")
      a3madkour-pub-bib/library-path
      (expand-file-name "~/org/notes/ref-notes/library.bib")
      a3madkour-pub-citations/ref-notes-dir (expand-file-name "~/org/notes/ref-notes/")
      a3madkour-library/notes-dir (expand-file-name "~/org/notes/")
      ;; The ingredient registry the recipe linter checks items against.  This
      ;; is the desktop path, for batch publishing; interactive sessions
      ;; override it through `a3madkour/org-file' (where the publish modules are
      ;; required) so the phone resolves it under /sdcard/org.
      a3madkour-ingredients/file (expand-file-name "~/org/recipes/ingredients.org")
      a3madkour-pub-recipes-dir (expand-file-name "~/org/recipes/"))
