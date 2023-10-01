(defpackage :lem-ncurses/text-buffer-impl
  (:use :cl))
(in-package :lem-ncurses/text-buffer-impl)

(defgeneric object-width (drawing-object))

(defmethod object-width ((drawing-object lem-core/display-3::void-object))
  0)

(defmethod object-width ((drawing-object lem-core/display-3::text-object))
  (lem-core:string-width (lem-core/display-3::text-object-string drawing-object)))

(defmethod object-width ((drawing-object lem-core/display-3::eol-cursor-object))
  0)

(defmethod object-width ((drawing-object lem-core/display-3::extend-to-eol-object))
  0)

(defmethod object-width ((drawing-object lem-core/display-3::line-end-object))
  0)

(defmethod object-width ((drawing-object lem-core/display-3::image-object))
  0)

(defmethod lem-if:view-width ((implementation lem-ncurses::ncurses) view)
  (lem-ncurses::ncurses-view-width view))

(defmethod lem-if:view-height ((implementation lem-ncurses::ncurses) view)
  (lem-ncurses::ncurses-view-height view))

(defgeneric draw-object (object x y window))

(defmethod draw-object ((object lem-core/display-3::void-object) x y window)
  (values))

(defmethod draw-object ((object lem-core/display-3::text-object) x y window)
  (let ((string (lem-core/display-3::text-object-string object))
        (attribute (lem-core/display-3::text-object-attribute object)))
    (when (and attribute (lem-core/display-3::cursor-attribute-p attribute))
      (let ((screen (lem:window-screen window)))
        (setf (lem-core::screen-last-print-cursor-x screen) x
              (lem-core::screen-last-print-cursor-y screen) y)))
    (lem-if:print (lem-core:implementation)
                  (lem-core::window-view window)
                  x
                  y
                  string
                  attribute)))

(defun color-to-hex-string (color)
  (format nil "#~2,'0X~2,'0X~2,'0X"
          (lem:color-red color)
          (lem:color-green color)
          (lem:color-blue color)))

(defmethod draw-object ((object lem-core/display-3::eol-cursor-object) x y window)
  (let ((screen (lem:window-screen window)))
    (setf (lem-core::screen-last-print-cursor-x screen) x
          (lem-core::screen-last-print-cursor-y screen) y))
  (lem-if:print (lem:implementation)
                (lem:window-view window)
                x
                y
                " "
                (lem:make-attribute :foreground
                                    (color-to-hex-string (lem-core/display-3::eol-cursor-object-color object)))))

(defmethod draw-object ((object lem-core/display-3::extend-to-eol-object) x y window)
  (lem-if:print (lem:implementation)
                (lem:window-view window)
                x
                y
                (make-string (- (lem:window-width window) x) :initial-element #\space)
                (lem:make-attribute :background
                                    (color-to-hex-string (lem-core/display-3::extend-to-eol-object-color object)))))

(defmethod draw-object ((object lem-core/display-3::line-end-object) x y window)
  (let ((string (lem-core/display-3::text-object-string object))
        (attribute (lem-core/display-3::text-object-attribute object)))
    (lem-if:print (lem-core:implementation)
                  (lem-core::window-view window)
                  (+ x (lem-core/display-3::line-end-object-offset object))
                  y
                  string
                  attribute)))

(defmethod draw-object ((object lem-core/display-3::image-object) x y window)
  (values))

(defmethod lem-core/display-3::%render-line ((implementation lem-ncurses::ncurses) window x y objects height)
  (let ((view (lem::window-view window)))
    (charms/ll:wmove (lem-ncurses::ncurses-view-scrwin view) y x)
    (charms/ll:wclrtoeol (lem-ncurses::ncurses-view-scrwin view))
    (loop :for object :in objects
          :do (draw-object object x y window)
              (incf x (lem-core/display-3::object-width object)))))

(defmethod lem-if:object-width ((implementation lem-ncurses::ncurses) drawing-object)
  (object-width drawing-object))

(defmethod lem-if:object-height ((implementation lem-ncurses::ncurses) drawing-object)
  1)

(defmethod lem-if:clear-to-end-of-window ((implementation lem-ncurses::ncurses) window y)
  (let* ((view (lem-core::window-view window))
         (win (lem-ncurses::ncurses-view-scrwin view)))
    (unless (= y (lem-if:view-height (lem:implementation) view))
      (charms/ll:wmove win y 0)
      (charms/ll:wclrtobot win))))
