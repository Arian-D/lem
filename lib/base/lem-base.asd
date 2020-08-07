(defsystem "lem-base"
  :depends-on ("uiop"
               "iterate"
               "alexandria"
               "cl-ppcre"
               "babel")
  :serial t
  :components ((:file "package")
               (:file "fileutil")
               (:file "util")
               (:file "errors")
               (:file "var")
               (:file "wide")
               (:file "macros")
               (:file "hooks")
               (:file "line")
               (:file "edit")
               (:file "buffer")
               (:file "buffer-insert")
               (:file "buffers")
               (:file "point")
               (:file "basic")
               (:file "search")
               (:file "parse-partial-sexp")
               (:file "syntax")
               (:file "syntax-parser")
               (:file "tmlanguage")
               (:file "encodings")
               (:file "file")
               (:file "indent")))
