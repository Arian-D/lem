(defpackage :lem-core/display-3
  (:use :cl)
  (:import-from :lem-core/display-2
                :attribute-equal-careful-null-and-symbol
                :eol-cursor-item
                :eol-cursor-item-attribute
                :extend-to-eol-item
                :extend-to-eol-item-color
                :line-end-item
                :line-end-item-text
                :line-end-item-attribute
                :line-end-item-offset
                :item-string
                :item-attribute
                :cursor-attribute-p
                :compute-items-from-logical-line
                :logical-line-equal
                :logical-line-left-content
                :compute-items-from-string-and-attributes
                :create-logical-line
                :collect-overlays
                :do-logical-line))
(in-package :lem-core/display-3)

(defvar *line-wrap*)

(defclass text-buffer-v2 (lem-core:text-buffer) ())

(defun attribute-image (attribute)
  (let ((attribute (lem-core:ensure-attribute attribute nil)))
    (when attribute
      (lem-core:attribute-value attribute 'image))))

(defun attribute-width (attribute)
  (let ((attribute (lem-core:ensure-attribute attribute nil)))
    (when attribute
      (lem-core:attribute-value attribute :width))))

(defun attribute-height (attribute)
  (let ((attribute (lem-core:ensure-attribute attribute nil)))
    (when attribute
      (lem-core:attribute-value attribute :height))))

(defun window-view-width (window)
  (lem-if:view-width (lem-core:implementation) (lem-core:window-view window)))

(defun window-view-height (window)
  (lem-if:view-height (lem-core:implementation) (lem-core:window-view window)))

(defun drawing-cache (window)
  (lem-core:window-parameter window 'redrawing-cache))

(defun (setf drawing-cache) (value window)
  (setf (lem-core:window-parameter window 'redrawing-cache) value))

(defun cjk-char-code-p (code)
  (or (<= #x4E00 code #x9FFF)
      (<= #x3040 code #x309F)
      (<= #x30A0 code #x30FF)
      (<= #xAC00 code #xD7A3)))

(defun latin-char-code-p (code)
  (or (<= #x0000 code #x007F)
      (<= #x0080 code #x00FF)
      (<= #x0100 code #x017F)
      (<= #x0180 code #x024F)))

(defun emoji-char-code-p (code)
  (or (<= #x1F300 code #x1F6FF)
      (<= #x1F900 code #x1F9FF)
      (<= #x1F600 code #x1F64F)
      (<= #x1F700 code #x1F77F)))

(defun braille-char-code-p (code)
  (<= #x2800 code #x28ff))

(defun icon-char-code-p (code)
  (lem-core:icon-value code :font))

(defun char-type (char)
  (let ((code (char-code char)))
    (cond ((eql code #x1f4c1)
           :folder)
          ((<= code 128)
           :latin)
          ((icon-char-code-p code)
           :icon)
          ((braille-char-code-p code)
           :braille)
          ((cjk-char-code-p code)
           :cjk)
          ((latin-char-code-p code)
           :latin)
          ((emoji-char-code-p code)
           :emoji)
          (t
           :emoji))))

(defclass drawing-object ()
  ())

(defclass void-object (drawing-object) ())

(defclass text-object (drawing-object)
  ((surface :initarg :surface :initform nil :accessor text-object-surface)
   (string :initarg :string :reader text-object-string)
   (attribute :initarg :attribute :reader text-object-attribute)
   (type :initarg :type :reader text-object-type)
   (within-cursor :initform nil :initarg :within-cursor :reader text-object-within-cursor-p)))

(defclass eol-cursor-object (drawing-object)
  ((color :initarg :color
          :reader eol-cursor-object-color)))

(defclass extend-to-eol-object (drawing-object)
  ((color :initarg :color
          :reader extend-to-eol-object-color)))

(defclass line-end-object (text-object)
  ((offset :initarg :offset
           :reader line-end-object-offset)))

(defclass image-object (drawing-object)
  ((image :initarg :image :reader image-object-image)
   (width :initarg :width :reader image-object-width)
   (height :initarg :height :reader image-object-height)
   (attribute :initarg :attribute :reader image-object-attribute)))

(defmethod cursor-object-p (drawing-object)
  nil)

(defmethod cursor-object-p ((drawing-object text-object))
  (text-object-within-cursor-p drawing-object))

(defmethod cursor-object-p ((drawing-object eol-cursor-object))
  t)

(defgeneric object-equal (drawing-object-1 drawing-object-2))

(defmethod object-equal (drawing-object-1 drawing-object-2)
  nil)

(defmethod object-equal ((drawing-object-1 void-object) (drawing-object-2 void-object))
  t)

(defmethod object-equal ((drawing-object-1 text-object) (drawing-object-2 text-object))
  (and (equal (text-object-string drawing-object-1)
              (text-object-string drawing-object-2))
       (attribute-equal-careful-null-and-symbol
        (text-object-attribute drawing-object-1)
        (text-object-attribute drawing-object-2))
       (eq (text-object-type drawing-object-1)
           (text-object-type drawing-object-2))
       (eq (text-object-within-cursor-p drawing-object-1)
           (text-object-within-cursor-p drawing-object-2))))

(defmethod object-equal ((drawing-object-1 eol-cursor-object) (drawing-object-2 eol-cursor-object))
  (equal (eol-cursor-object-color drawing-object-1)
         (eol-cursor-object-color drawing-object-2)))

(defmethod object-equal ((drawing-object-1 extend-to-eol-object) (drawing-object-2 extend-to-eol-object))
  (equal (extend-to-eol-object-color drawing-object-1)
         (extend-to-eol-object-color drawing-object-2)))

(defmethod object-equal ((drawing-object-1 line-end-object) (drawing-object-2 line-end-object))
  (equal (line-end-object-offset drawing-object-1)
         (line-end-object-offset drawing-object-2)))

(defmethod object-equal ((drawing-object-1 image-object) (drawing-object-2 image-object))
  nil)

(defun object-width (drawing-object)
  (lem-if:object-width (lem-core:implementation) drawing-object))

(defun object-height (drawing-object)
  (lem-if:object-height (lem-core:implementation) drawing-object))

;;; draw-object
(defun split-string-by-character-type (string)
  (loop :with pos := 0 :and items := '()
        :while (< pos (length string))
        :for type := (char-type (char string pos))
        :do (loop :with start := pos
                  :while (and (< pos (length string))
                              (eq type (char-type (char string pos))))
                  :do (incf pos)
                  :finally (push (cons type (subseq string start pos)) items))
        :finally (return (nreverse items))))

(defun make-line-end-object (string attribute type offset)
  (let ((attribute (and attribute (lem-core:ensure-attribute attribute))))
    (make-instance 'line-end-object
                   :offset offset
                   :string string
                   :attribute attribute
                   :type type)))

(defun make-text-object (string attribute type)
  (let ((attribute (and attribute (lem-core:ensure-attribute attribute))))
    (make-instance 'text-object
                   :string string
                   :attribute attribute
                   :type type
                   :within-cursor (and attribute
                                       (cursor-attribute-p attribute)))))

(defun create-drawing-object (item)
  (cond ((and *line-wrap* (typep item 'eol-cursor-item))
         (list (make-instance 'eol-cursor-object
                              :color (lem-core:parse-color
                                      (lem-core:attribute-background
                                       (eol-cursor-item-attribute item))))))
        ((typep item 'extend-to-eol-item)
         (list (make-instance 'extend-to-eol-object :color (extend-to-eol-item-color item))))
        ((typep item 'line-end-item)
         (let ((string (line-end-item-text item))
               (attribute (line-end-item-attribute item)))
           (loop :for (type . string) :in (split-string-by-character-type string)
                 :unless (alexandria:emptyp string)
                 :collect (make-line-end-object string
                                                attribute
                                                type
                                                (line-end-item-offset item)))))
        (t
         (let ((string (item-string item))
               (attribute (item-attribute item)))
           (cond ((alexandria:emptyp string)
                  (list (make-instance 'void-object)))
                 ((and attribute (attribute-image attribute))
                  (list (make-instance 'image-object
                                       :image (attribute-image attribute)
                                       :width (attribute-width attribute)
                                       :height (attribute-height attribute)
                                       :attribute attribute)))
                 (t
                  (loop :for (type . string) :in (split-string-by-character-type string)
                        :unless (alexandria:emptyp string)
                        :collect (make-text-object string attribute type))))))))

(defun create-drawing-objects (logical-line)
  (multiple-value-bind (items line-end-item)
      (compute-items-from-logical-line logical-line)
    (append (loop :for item :in items
                  :append (create-drawing-object item))
            (when line-end-item
              (create-drawing-object line-end-item)))))

(defun make-letter-object (character attribute)
  (make-text-object (string character)
                    attribute
                    (char-type character)))

(defun explode-object (text-object)
  (check-type text-object text-object)
  (loop :for c :across (text-object-string text-object)
        :collect (make-letter-object c (text-object-attribute text-object))))

(defun separate-objects-by-width (objects view-width)
  (loop
    :until (null objects)
    :collect (loop :with total-width := 0
                   :and physical-line-objects := '()
                   :for object := (pop objects)
                   :while object
                   :do (cond ((<= view-width (+ total-width (object-width object)))
                              (cond ((and (typep object 'text-object)
                                          (< 1 (length (text-object-string object))))
                                     (setf objects (nconc (explode-object object) objects)))
                                    (t
                                     (push object objects)
                                     (push (make-letter-object #\\ nil)
                                           physical-line-objects)
                                     (return (nreverse physical-line-objects)))))
                             (t
                              (incf total-width (object-width object))
                              (push object physical-line-objects)))
                   :finally (return (nreverse physical-line-objects)))))

(defun render-line (window x y objects height)
  (%render-line (lem-core:implementation) window x y objects height))

(defun validate-cache-p (window y height objects)
  (loop :for (cache-y cache-height cache-objects) :in (drawing-cache window)
        :when (and (= y cache-y)
                   (= height cache-height)
                   (alexandria:length= objects cache-objects)
                   (every #'object-equal objects cache-objects))
        :return t))

(defun invalidate-cache (window y height)
  (setf (drawing-cache window)
        (remove-if (lambda (elt)
                     (destructuring-bind (cache-y cache-height cache-logical-line) elt
                       (declare (ignore cache-logical-line))
                       (not (or (<= (+ y height)
                                    cache-y)
                                (<= (+ cache-y cache-height)
                                    y)))))
                   (drawing-cache window))))

(defun update-and-validate-cache-p (window y height objects)
  (cond ((validate-cache-p window y height objects) t)
        (t
         (invalidate-cache window y height)
         (push (list y height objects)
               (drawing-cache window))
         nil)))

(defun max-height-of-objects (objects)
  (loop :for object :in objects
        :maximize (object-height object)))

(defun redraw-logical-line-when-line-wrapping (window y logical-line)
  (let* ((left-side-objects
           (alexandria:when-let (content (logical-line-left-content logical-line))
             (mapcan #'create-drawing-object
                     (compute-items-from-string-and-attributes
                      (lem-base::content-string content)
                      (lem-base::content-attributes content)))))
         (left-side-width
           (loop :for object :in left-side-objects :sum (object-width object)))
         (objects-per-physical-line
           (separate-objects-by-width
            (append left-side-objects (create-drawing-objects logical-line))
            (window-view-width window))))
    (loop :for objects :in objects-per-physical-line
          :for height := (max-height-of-objects objects)
          :for x := 0 :then left-side-width
          :do (unless (update-and-validate-cache-p window y height objects)
                (render-line window x y objects height))
              (incf y height)
          :sum height)))

(defun find-cursor-object (objects)
  (loop :for object :in objects
        :and x := 0 :then (+ x (object-width object))
        :when (cursor-object-p object)
        :return (values object x)))

(defun horizontal-scroll-start (window)
  (or (lem-core:window-parameter window 'horizontal-scroll-start)
      0))

(defun (setf horizontal-scroll-start) (x window)
  (setf (lem-core:window-parameter window 'horizontal-scroll-start) x))

(defun extract-object-in-display-range (objects start-x end-x)
  (loop :for object :in objects
        :and x := 0 :then (+ x (object-width object))
        :when (and (<= start-x x)
                   (<= (+ x (object-width object)) end-x))
        :collect object))

(defun redraw-logical-line-when-horizontal-scroll (window y logical-line)
  (let* ((left-side-objects
           (alexandria:when-let (content (logical-line-left-content logical-line))
             (mapcan #'create-drawing-object
                     (compute-items-from-string-and-attributes
                      (lem-base::content-string content)
                      (lem-base::content-attributes content)))))
         (left-side-width
           (loop :for object :in left-side-objects :sum (object-width object)))
         (objects
           (append left-side-objects (create-drawing-objects logical-line)))
         (height
           (max-height-of-objects objects)))
    (multiple-value-bind (cursor-object cursor-x)
        (find-cursor-object objects)
      (when cursor-object
        (let ((width (- (window-view-width window) left-side-width)))
          (cond ((< cursor-x (horizontal-scroll-start window))
                 (setf (horizontal-scroll-start window) cursor-x))
                ((< (+ (horizontal-scroll-start window)
                       width)
                    (+ cursor-x (object-width cursor-object)))
                 (setf (horizontal-scroll-start window)
                       (+ (- cursor-x width)
                          (object-width cursor-object))))))
        (setf objects
              (extract-object-in-display-range
               (mapcan (lambda (object)
                         (if (typep object 'text-object)
                             (explode-object object)
                             (list object)))
                       objects)
               (horizontal-scroll-start window)
               (+ (horizontal-scroll-start window)
                  (window-view-width window)))))
      (unless (update-and-validate-cache-p window y height objects)
        (render-line window 0 y objects height)))
    height))

(defun redraw-lines (window)
  (let* ((*line-wrap* (lem-core:variable-value 'lem-core:line-wrap
                                               :default (lem-core:window-buffer window)))
         (redraw-fn (if *line-wrap*
                        #'redraw-logical-line-when-line-wrapping
                        #'redraw-logical-line-when-horizontal-scroll)))
    (let ((y 0)
          (height (window-view-height window)))
      (block outer
        (do-logical-line (logical-line window)
          (incf y (funcall redraw-fn window y logical-line))
          (unless (< y height)
            (return-from outer))))
      (lem-if:clear-to-end-of-window (lem-core:implementation) window y))))

(defun redraw-buffer-internal (buffer window force)
  (assert (eq buffer (lem-core:window-buffer window)))
  (when (or force
            (lem-core::screen-modified-p (lem-core:window-screen window)))
    (setf (drawing-cache window) '()))
  (redraw-lines window)
  (lem-core::update-screen-cache (lem-core:window-screen window) buffer))

(defmethod lem-core::redraw-buffer (implementation (buffer text-buffer-v2) window force)
  (redraw-buffer-internal buffer window force))

(lem-core:define-command change-buffer-to-v2 () ()
  (change-class (lem-core:current-buffer) 'text-buffer-v2))

(lem-core:define-command change-buffer-to-v1 () ()
  (change-class (lem-core:current-buffer) 'lem-base:text-buffer))
