(defpackage :lem-vi-mode/commands/utils
  (:use :cl
        :lem)
  (:import-from :lem-vi-mode/jump-motions
                :with-jump-motion)
  (:import-from :lem-vi-mode/visual
                :visual-p
                :visual-line-p
                :apply-visual-range
                :vi-visual-end)
  (:import-from :alexandria
                :with-gensyms)
  (:export :bolp
           :eolp
           :goto-eol
           :fall-within-line
           :read-universal-argument
           :*cursor-offset*
           :vi-command
           :vi-motion
           :vi-motion-type
           :vi-operator
           :define-vi-motion
           :define-vi-operator))
(in-package :lem-vi-mode/commands/utils)

(defun bolp (point)
  "Return t if POINT is at the beginning of a line."
  (zerop (point-charpos point)))

(defun eolp (point)
  "Return t if POINT is at the end of line."
  (let ((len (length (line-string point))))
    (or (zerop len)
        (>= (point-charpos point)
            (1- len)))))

(defun goto-eol (point)
  "Goto end of a line."
  (line-end point)
  (unless (bolp point)
    (character-offset point *cursor-offset*)))

(defun fall-within-line (point)
  (when (eolp point)
    (goto-eol point)))

(defun read-universal-argument ()
  (loop :for key := (read-key)
        :for char := (key-to-char key)
        :while (and char (digit-char-p char))
        :collect (digit-char-p char) :into digits
        :finally (unread-key key)
                 (return-from read-universal-argument
                   (and digits
                        (parse-integer (format nil "~{~D~}" digits))))))

(defclass vi-command () ())

(defclass vi-motion (vi-command)
  ((type :type keyword
         :initarg :type
         :initform :exclusive
         :accessor vi-motion-type)))

(defclass vi-operator (vi-command) ())

(defvar *vi-origin-point*)
(defvar *cursor-offset* -1)

(defmacro define-vi-motion (name arg-list (&key type jump) &body body)
  (check-type type (or null (member :inclusive :exclusive :line)))
  (check-type jump boolean)
  (with-gensyms (n)
    `(define-command (,name (:advice-classes vi-motion)
                            (:initargs ,@(and type
                                              `(:type ,type))))
         (&optional (,n 1)) ("p")
       (with-point ((*vi-origin-point* (current-point)))
         (,(if jump 'with-jump-motion 'progn)
           ,(if arg-list
                `(destructuring-bind ,arg-list (list ,n)
                   ,@body)
                `(progn ,@body)))))))

(defvar *vi-operator-arguments* nil)

(defmacro define-vi-operator (name arg-list (&key motion keep-visual restore-point) &body body)
  (with-gensyms (start end n type command command-name)
    `(define-command (,name (:advice-classes vi-operator)) (&optional (,n 1)) ("p")
       (with-point ((*vi-origin-point* (current-point)))
         (unwind-protect
             (if *vi-operator-arguments*
                 (destructuring-bind ,(and arg-list
                                           `(&optional ,@arg-list))
                     (subseq *vi-operator-arguments* 0 ,(length arg-list))
                   ,@body)
                 (with-point ((,start (current-point))
                              (,end (current-point)))
                   (let ((,type (if (visual-line-p)
                                    :line
                                    :exclusive)))
                     (if (visual-p)
                         (apply-visual-range
                           (lambda (vstart vend)
                             (setf ,start vstart
                                   ,end vend)))
                         (if ',motion
                             (progn
                               (let ((*cursor-offset* 0))
                                 (call-command ',motion ,n))
                               (let ((,command (get-command ',motion)))
                                 (when (typep ,command 'vi-motion)
                                   (setf ,type (vi-motion-type ,command))))
                               (move-point ,end (current-point)))
                             (let* ((,n (or (read-universal-argument) ,n))
                                    (,command-name (read-command))
                                    (,command (get-command ,command-name)))
                               (typecase ,command
                                 (vi-operator
                                   ;; Recursive call of the operator like 'dd', 'cc'
                                   (when (eq ,command-name ',name)
                                     (setf ,type :line)
                                     (line-start ,start)
                                     (line-offset ,end (1- ,n))
                                     (line-end ,end)))
                                 (otherwise
                                   (let ((*cursor-offset* 0))
                                     (ignore-errors
                                       (call-command ,command ,n)))
                                   (when (and (typep ,command 'vi-motion)
                                              (point/= ,end (current-point)))
                                     (setf ,type (vi-motion-type ,command)))
                                   (move-point ,end (current-point)))))))
                     (when (point< ,end ,start)
                       (rotatef ,start ,end))
                     (ecase ,type
                       (:exclusive)
                       (:inclusive (character-offset ,end 1))
                       (:line (unless (visual-p)
                                (line-start ,start)
                                (line-end ,end))))
                     (let ((*vi-operator-arguments* (list ,start ,end ,type)))
                       (destructuring-bind ,(and arg-list
                                                 `(&optional ,@arg-list))
                           (subseq *vi-operator-arguments* 0 ,(length arg-list))
                         ,@body)))))
           ,@(when restore-point
               '((move-point (current-point) *vi-origin-point*)))
           ,@(unless keep-visual
               '((when (visual-p) (vi-visual-end)))))))))
