(in-package :lem)

(export '(*keymaps*
          keymap
          make-keymap
          *global-keymap*
          undefined-key
          define-key
          keyseq-to-string
          find-keybind
          insertion-key-p
          lookup-keybind))

(defvar *keymaps* nil)

(defstruct (keymap (:constructor %make-keymap) (:print-function %print-keymap))
  undef-hook
  insertion-hook
  parent
  table
  function-table
  name)

(defun %print-keymap (object stream depth)
  (declare (ignorable depth))
  (print-unreadable-object (object stream :identity t :type t)
    (when (keymap-name object)
      (format stream "~A" (keymap-name object)))))

(defun make-keymap (&key undef-hook insertion-hook parent name)
  (let ((keymap (%make-keymap
                 :undef-hook undef-hook
                 :insertion-hook insertion-hook
                 :parent parent
                 :table (make-hash-table :test 'eq)
                 :function-table (make-hash-table :test 'eq)
                 :name name)))
    (push keymap *keymaps*)
    keymap))

(defun define-key (keymap keyspec symbol)
  (check-type symbol symbol)
  (let ((keys (typecase keyspec
                (symbol
                 (setf (gethash keyspec (keymap-function-table keymap)) symbol)
                 (return-from define-key))
                (string (parse-keyspec keyspec)))))
    (define-key-internal keymap keys symbol)))

(defun define-key-internal (keymap keys symbol)
  (loop :with table := (keymap-table keymap)
        :for rest :on (uiop:ensure-list keys)
        :for k := (car rest)
        :do (cond ((null (cdr rest))
                   (setf (gethash k table) symbol))
                  (t
                   (let ((next (gethash k table)))
                     (if next
                         (setf table next)
                         (let ((new-table (make-hash-table :test 'eq)))
                           (setf (gethash k table) new-table)
                           (setf table new-table))))))))

(defun parse-keyspec (string)
  (labels ((fail ()
             (editor-error "parse error: ~A" string))
           (parse (str)
             (loop :with ctrl :and meta :and super :and hypher :and shift
                   :do (cond
                         ((ppcre:scan "^[cmshCMSH]-" str)
                          (ecase (char-downcase (char str 0))
                            ((#\c) (setf ctrl t))
                            ((#\m) (setf meta t))
                            ((#\s) (setf super t))
                            ((#\h) (setf hypher t)))
                          (setf str (subseq str 2)))
                         ((ppcre:scan "^[sS]hift-" str)
                          (setf shift t)
                          (setf str (subseq str 6)))
                         ((string= str "")
                          (fail))
                         ((and (not (insertion-key-sym-p str))
                               (not (named-key-sym-p str)))
                          (fail))
                         (t
                          (cond ((and ctrl (string= str "i"))
                                 (setf ctrl nil
                                       str "Tab"))
                                ((and ctrl (string= str "m"))
                                 (setf ctrl nil
                                       str "Return")))
                          (return (make-key :ctrl ctrl
                                            :meta meta
                                            :super super
                                            :hypher hypher
                                            :shift shift
                                            :sym (or (named-key-sym-p str)
                                                     str))))))))
    (mapcar #'parse (uiop:split-string string :separator " "))))

(defun keyseq-to-string (kseq)
  (with-output-to-string (out)
    (loop :for key* :on kseq
          :for key := (first key*)
          :do (princ key out)
              (when (rest key*)
                (write-char #\space out)))))

(defun keymap-find-keybind (keymap key cmd)
  (let ((table (keymap-table keymap)))
    (labels ((f (k)
               (let ((cmd (gethash k table)))
                 (if (hash-table-p cmd)
                     (setf table cmd)
                     cmd))))
      (let ((parent (keymap-parent keymap)))
        (when parent
          (setf cmd (keymap-find-keybind parent key cmd))))
      (or (etypecase key
            (key
             (f key))
            (list
             (let (cmd)
               (dolist (k key)
                 (unless (setf cmd (f k))
                   (return)))
               cmd)))
          (gethash cmd (keymap-function-table keymap))
          (and (keymap-insertion-hook keymap)
               (insertion-key-p key)
               (keymap-insertion-hook keymap))
          (keymap-undef-hook keymap)
          cmd))))

(defun insertion-key-p (key)
  (let* ((key (typecase key
                (list (first key))
                (otherwise key)))
         (sym (key-sym key)))
    (cond ((match-key key :sym "Return") #\Return)
          ((match-key key :sym "Tab") #\Tab)
          ((match-key key :sym "Space") #\Space)
          ((and (insertion-key-sym-p sym)
                (match-key key :sym sym))
           (char sym 0)))))

(defun keymap-flatten-map (keymap fun)
  (labels ((f (table prefix)
             (maphash (lambda (k v)
                        (if (hash-table-p v)
                            (f v (cons k prefix))
                            (funcall fun (reverse (cons k prefix)) v)))
                      table)))
    (f (keymap-table keymap) nil)))

(defvar *global-keymap* (make-keymap :name '*global-keymap*
                                     :undef-hook 'self-insert))

(define-command undefined-key () ()
  (editor-error "Key not found: ~A"
                (keyseq-to-string (last-read-key-sequence))))

(defun lookup-keybind (key)
  (let (cmd)
    (loop with buffer = (current-buffer)
          for mode in (nreverse (append (buffer-minor-modes buffer)
                                        *global-minor-mode-list*
                                        (list (buffer-major-mode buffer)
                                              (current-global-mode))))
          do (when (mode-keymap mode)
               (setf cmd (keymap-find-keybind (mode-keymap mode) key cmd))))
    cmd))

(defun find-keybind (key)
  (let ((cmd (lookup-keybind key)))
    (when (symbolp cmd)
      cmd)))

(defun abort-key-p (key)
  (and (key-p key)
       (eq 'keyboard-quit (lookup-keybind key))))
