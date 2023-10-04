(defpackage :lem-sdl2/text-buffer-impl
  (:use :cl))
(in-package :lem-sdl2/text-buffer-impl)

(defmethod lem-if:view-width ((implementation lem-sdl2::sdl2) view)
  (* (lem-sdl2::char-width) (lem-sdl2::view-width view)))

(defmethod lem-if:view-height ((implementation lem-sdl2::sdl2) view)
  (* (lem-sdl2::char-height) (lem-sdl2::view-height view)))

(defun set-cursor-position (window x y)
  (let ((view (lem:window-view window)))
    (setf (lem-sdl2::view-last-cursor-x view) x
          (lem-sdl2::view-last-cursor-y view) y)))

(defun attribute-font (attribute)
  (let ((attribute (lem:ensure-attribute attribute nil)))
    (when attribute
      (lem:attribute-value attribute 'font))))

(defun get-font (&key attribute type bold)
  (or (alexandria:when-let (attribute (and attribute (lem:ensure-attribute attribute)))
        (attribute-font attribute))
      (lem-sdl2::get-display-font lem-sdl2::*display* :type type :bold bold)))

(defgeneric get-surface (drawing-object))

(defmethod get-surface :around (drawing-object)
  (or (lem-core/display/physical-line::text-object-surface drawing-object)
      (setf (lem-core/display/physical-line::text-object-surface drawing-object)
            (call-next-method))))

(defmethod get-surface ((drawing-object lem-core/display/physical-line::text-object))
  (let* ((attribute (lem-core/display/physical-line::text-object-attribute drawing-object))
         (foreground (lem-core:attribute-foreground-with-reverse attribute)))
    (cffi:with-foreign-string (c-string (lem-core/display/physical-line::text-object-string drawing-object))
      (sdl2-ttf:render-utf8-blended
       (get-font :attribute attribute
                 :type (lem-core/display/physical-line::text-object-type drawing-object)
                 :bold (and attribute (lem:attribute-bold attribute)))
       c-string
       (lem:color-red foreground)
       (lem:color-green foreground)
       (lem:color-blue foreground)
       0))))

(defmethod get-surface ((drawing-object lem-core/display/physical-line::icon-object))
  (let* ((string (lem-core/display/physical-line::text-object-string drawing-object))
         (attribute (lem-core/display/physical-line::text-object-attribute drawing-object))
         (font (lem-sdl2::icon-font (char (lem-core/display/physical-line::text-object-string drawing-object) 0)))
         (foreground (lem-core:attribute-foreground-with-reverse attribute)))
    (cffi:with-foreign-string (c-string string)
      (sdl2-ttf:render-utf8-blended font
                                    c-string
                                    (lem:color-red foreground)
                                    (lem:color-green foreground)
                                    (lem:color-blue foreground)
                                    0))))

(defmethod get-surface ((drawing-object lem-core/display/physical-line::folder-object))
  (sdl2-image:load-image
   (lem-sdl2::get-resource-pathname
    "resources/open-folder.png")))

(defgeneric object-width (drawing-object))

(defmethod object-width ((drawing-object lem-core/display/physical-line::void-object))
  0)

(defmethod object-width ((drawing-object lem-core/display/physical-line::text-object))
  (sdl2:surface-width (get-surface drawing-object)))

(defmethod object-width ((drawing-object lem-core/display/physical-line::control-character-object))
  (* 2 (lem-sdl2::char-width)))

(defmethod object-width ((drawing-object lem-core/display/physical-line::icon-object))
  (sdl2:surface-width (get-surface drawing-object)))

(defmethod object-width ((drawing-object lem-core/display/physical-line::folder-object))
  (* 2 (lem-sdl2::char-width)))

(defmethod object-width ((drawing-object lem-core/display/physical-line::emoji-object))
  (* (lem-sdl2::char-width) 2 (length (lem-core/display/physical-line::text-object-string drawing-object))))

(defmethod object-width ((drawing-object lem-core/display/physical-line::eol-cursor-object))
  0)

(defmethod object-width ((drawing-object lem-core/display/physical-line::extend-to-eol-object))
  0)

(defmethod object-width ((drawing-object lem-core/display/physical-line::line-end-object))
  (sdl2:surface-width (get-surface drawing-object)))

(defmethod object-width ((drawing-object lem-core/display/physical-line::image-object))
  (or (lem-core/display/physical-line::image-object-width drawing-object)
      (sdl2:surface-width (lem-core/display/physical-line::image-object-image drawing-object))))


(defgeneric object-height (drawing-object))

(defmethod object-height ((drawing-object lem-core/display/physical-line::void-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::text-object))
  (sdl2:surface-height (get-surface drawing-object)))

(defmethod object-height ((drawing-object lem-core/display/physical-line::icon-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::control-character-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::folder-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::emoji-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::eol-cursor-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::extend-to-eol-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::line-end-object))
  (lem-sdl2::char-height))

(defmethod object-height ((drawing-object lem-core/display/physical-line::image-object))
  (or (lem-core/display/physical-line::image-object-height drawing-object)
      (sdl2:surface-height (lem-core/display/physical-line::image-object-image drawing-object))))

(defmethod lem-if:object-width ((implementation lem-sdl2::sdl2) drawing-object)
  (object-width drawing-object))

(defmethod lem-if:object-height ((implementation lem-sdl2::sdl2) drawing-object)
  (object-height drawing-object))

;;; draw-object
(defmethod draw-object ((drawing-object lem-core/display/physical-line::void-object) x bottom-y window)
  0)

(defmethod draw-object ((drawing-object lem-core/display/physical-line::text-object) x bottom-y window)
  (let* ((surface-width (object-width drawing-object))
         (surface-height (object-height drawing-object))
         (attribute (lem-core/display/physical-line::text-object-attribute drawing-object))
         (background (lem-core:attribute-background-with-reverse attribute))
         (texture (sdl2:create-texture-from-surface
                   (lem-sdl2::current-renderer)
                   (get-surface drawing-object)))
         (y (- bottom-y surface-height)))
    (when (and attribute (lem-core/display/physical-line::cursor-attribute-p attribute))
      (set-cursor-position window x y))
    (sdl2:with-rects ((rect x y surface-width surface-height))
      (lem-sdl2::set-color background)
      (sdl2:render-fill-rect (lem-sdl2::current-renderer) rect))
    (lem-sdl2::render-texture (lem-sdl2::current-renderer)
                              texture
                              x
                              y
                              surface-width
                              surface-height)
    (sdl2:destroy-texture texture)
    (when (and attribute
               (lem:attribute-underline attribute))
      (lem-sdl2::render-line x
                             (1- (+ y surface-height))
                             (+ x surface-width)
                             (1- (+ y surface-height))
                             :color (let ((underline (lem:attribute-underline attribute)))
                                      (if (eq underline t)
                                          (lem-sdl2::attribute-foreground-color attribute)
                                          (or (lem:parse-color underline)
                                              (lem-sdl2::attribute-foreground-color attribute))))))
    surface-width))

(defmethod draw-object ((drawing-object lem-core/display/physical-line::eol-cursor-object) x bottom-y window)
  (lem-sdl2::set-color (lem-core/display/physical-line::eol-cursor-object-color drawing-object))
  (let ((y (- bottom-y (object-height drawing-object))))
    (set-cursor-position window x y)
    (sdl2:with-rects ((rect x
                            y
                            (lem-sdl2::char-width)
                            (object-height drawing-object)))
      (sdl2:render-fill-rect (lem-sdl2::current-renderer) rect)))
  (object-width drawing-object))

(defmethod draw-object ((drawing-object lem-core/display/physical-line::extend-to-eol-object) x bottom-y window)
  (lem-sdl2::set-color (lem-core/display/physical-line::extend-to-eol-object-color drawing-object))
  (sdl2:with-rects ((rect x
                          (- bottom-y (lem-sdl2::char-height))
                          (- (lem-core/display/physical-line::window-view-width window) x)
                          (lem-sdl2::char-height)))
    (sdl2:render-fill-rect (lem-sdl2::current-renderer)
                           rect))
  (object-width drawing-object))

(defmethod draw-object ((drawing-object lem-core/display/physical-line::line-end-object) x bottom-y window)
  (call-next-method drawing-object
                    (+ x
                       (* (lem-core/display/physical-line::line-end-object-offset drawing-object)
                          (lem-sdl2::char-width)))
                    bottom-y))

(defmethod draw-object ((drawing-object lem-core/display/physical-line::image-object) x bottom-y window)
  (let* ((surface-width (object-width drawing-object))
         (surface-height (object-height drawing-object))
         (texture (sdl2:create-texture-from-surface (lem-sdl2::current-renderer)
                                                    (lem-core/display/physical-line::image-object-image drawing-object)))
         (y (- bottom-y surface-height)))
    (lem-sdl2::render-texture (lem-sdl2::current-renderer) texture x y surface-width surface-height)
    (sdl2:destroy-texture texture)
    surface-width))

(defun redraw-physical-line (window x y objects height)
  (loop :with current-x := x
        :for object :in objects
        :do (incf current-x (draw-object object current-x (+ y height) window))))

(defun clear-to-end-of-line (window x y height)
  (sdl2:with-rects ((rect x y (- (lem-core/display/physical-line::window-view-width window) x) height))
    (lem-sdl2::set-render-color lem-sdl2::*display* (lem-sdl2::display-background-color lem-sdl2::*display*))
    (sdl2:render-fill-rect (lem-sdl2::current-renderer) rect)))

(defmethod lem-if:render-line ((implementation lem-sdl2::sdl2) window x y objects height)
  (clear-to-end-of-line window 0 y height)
  (redraw-physical-line window x y objects height))

(defmethod lem-if:clear-to-end-of-window ((implementation lem-sdl2::sdl2) window y)
  (lem-sdl2::set-render-color
   lem-sdl2::*display*
   (lem-sdl2::display-background-color lem-sdl2::*display*))
  (sdl2:with-rects ((rect 0
                          y
                          (lem-core/display/physical-line::window-view-width window)
                          (- (lem-core/display/physical-line::window-view-height window) y)))
    (sdl2:render-fill-rect (lem-sdl2::current-renderer) rect)))

(defmethod lem-core:redraw-buffer :before ((implementation lem-sdl2::sdl2) buffer window force)
  (sdl2:set-render-target (lem-sdl2::current-renderer)
                          (lem-sdl2::view-texture (lem:window-view window))))

(defmethod lem-core:redraw-buffer :around ((implementation lem-sdl2::sdl2) buffer window force)
  (sdl2:in-main-thread ()
    (call-next-method)))
