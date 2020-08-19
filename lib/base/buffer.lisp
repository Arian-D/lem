(in-package :lem-base)

(export '(fundamental-mode
          primordial-buffer
          current-buffer
          make-buffer
          buffer
          bufferp
          buffer-start-point
          buffer-end-point
          deleted-buffer-p
          buffer-name
          buffer-temporary-p
          buffer-modified-tick
          buffer-modified-p
          buffer-read-only-p
          buffer-syntax-table
          buffer-major-mode
          buffer-minor-modes
          buffer-mark-p
          buffer-mark
          buffer-point
          buffer-nlines
          buffer-enable-undo-p
          buffer-enable-undo
          buffer-disable-undo
          buffer-filename
          buffer-directory
          buffer-unmark
          buffer-mark-cancel
          buffer-rename
          buffer-undo
          buffer-redo
          buffer-undo-boundary
          buffer-value
          buffer-unbound
          clear-buffer-variables))

(export '(%buffer-keep-binfo
          %buffer-clear-keep-binfo))

(defparameter +primordial-buffer-name+ "*tmp*")

(defclass buffer ()
  ((name
    :initform nil
    :initarg :name
    :accessor buffer-%name)
   (%filename
    :initform nil
    :initarg :%filename
    :accessor buffer-%filename)
   (%directory
    :initform nil
    :initarg :%directory
    :accessor buffer-%directory)
   (%modified-p
    :initform nil
    :reader buffer-modified-tick
    :accessor buffer-%modified-p)
   (%enable-undo-p
    :initform nil
    :initarg :%enable-undo-p
    :accessor buffer-%enable-undo-p)
   (temporary
    :initarg :temporary
    :reader buffer-temporary-p)
   (read-only-p
    :initform nil
    :initarg :read-only-p
    :accessor buffer-read-only-p)
   (syntax-table
    :initform (fundamental-syntax-table)
    :initarg :syntax-table
    :accessor buffer-syntax-table)
   (major-mode
    :initform nil
    :initarg :major-mode
    :accessor buffer-major-mode)
   (minor-modes
    :initform nil
    :initarg :minor-modes
    :accessor buffer-minor-modes)
   (start-point
    :initform nil
    :initarg :start-point
    :writer set-buffer-start-point
    :reader buffer-start-point)
   (end-point
    :initform nil
    :initarg :end-point
    :writer set-buffer-end-point
    :reader buffer-end-point)
   (mark-p
    :initform nil
    :initarg :mark-p
    :accessor buffer-mark-p)
   (mark
    :initform nil
    :initarg :mark
    :accessor buffer-mark)
   (point
    :initform nil
    :initarg :point
    :accessor buffer-point)
   (keep-binfo
    :initform nil
    :initarg :keep-binfo
    :accessor %buffer-keep-binfo)
   (points
    :initform nil
    :accessor buffer-points)
   (nlines
    :initform nil
    :initarg :nlines
    :accessor buffer-nlines)
   (edit-history
    :initform (make-array 0 :adjustable t :fill-pointer 0)
    :accessor buffer-edit-history)
   (redo-stack
    :initform nil
    :accessor buffer-redo-stack)
   (encoding
    :initform nil
    :initarg :encoding
    :accessor buffer-encoding)
   (last-write-date
    :initform nil
    :initarg :last-write-date
    :accessor buffer-last-write-date)
   (variables
    :initform nil
    :initarg :variables
    :accessor buffer-variables))
  (:documentation
   "`buffer`はバッファ名、ファイル名、テキスト、テキストを指す位置等が入った、
文書を管理するオブジェクトです。  
複数の`buffer`はリストで管理されています。"))

;; workaround for windows
#+win32
(defmethod initialize-instance :after ((buffer buffer) &rest initargs)
  "set default buffer encoding to utf-8"
  (setf (buffer-encoding buffer) (encoding :utf-8 :lf)))

(setf (documentation 'buffer-point 'function) "`buffer`の現在の`point`を返します。")
(setf (documentation 'buffer-mark 'function) "`buffer`の現在のマークの`point`を返します。")
(setf (documentation 'buffer-start-point 'function) "`buffer`の最初の位置の`point`を返します。")
(setf (documentation 'buffer-end-point 'function) "`buffer`の最後の位置の`point`を返します。")

(defvar *current-buffer*)

(defun primordial-buffer ()
  (make-buffer +primordial-buffer-name+))

(defun current-buffer ()
  "現在の`buffer`を返します。"
  (unless (boundp '*current-buffer*)
    (setf *current-buffer*
          (primordial-buffer)))
  *current-buffer*)

(defun (setf current-buffer) (buffer)
  "現在の`buffer`を変更します。"
  (check-type buffer buffer)
  (setf *current-buffer* buffer))

(defvar *undo-modes* '(:edit :undo :redo))
(defvar *undo-mode* :edit)

(defun last-edit-history (buffer)
  (when (< 0 (fill-pointer (buffer-edit-history buffer)))
    (aref (buffer-edit-history buffer)
          (1- (fill-pointer (buffer-edit-history buffer))))))

(defun make-buffer (name &key temporary read-only-p (enable-undo-p t)
                              (syntax-table (fundamental-syntax-table)))
  "バッファ名が`name`のバッファがバッファリストに含まれていれば
そのバッファを返し、無ければ作成します。  
`read-only-p`は読み込み専用にするか。  
`enable-undo-p`はアンドゥを有効にするか。  
`syntax-table`はそのバッファの構文テーブルを指定します。  
`temporary`が非NILならバッファリストに含まないバッファを作成します。  
引数で指定できるオプションは`temporary`がNILで既にバッファが存在する場合は無視します。
"
  (unless temporary
    (uiop:if-let ((buffer (get-buffer name)))
      (return-from make-buffer buffer)))
  (let ((buffer (make-instance 'buffer
                               :name name
                               :read-only-p read-only-p
                               :%enable-undo-p enable-undo-p
                               :temporary temporary
                               :major-mode 'fundamental-mode
                               :syntax-table syntax-table)))
    (setf (buffer-mark-p buffer) nil)
    (setf (buffer-mark buffer) nil)
    (setf (%buffer-keep-binfo buffer) nil)
    (setf (buffer-nlines buffer) 1)
    (setf (buffer-%modified-p buffer) 0)
    (setf (buffer-redo-stack buffer) nil)
    (setf (buffer-variables buffer) (make-hash-table :test 'equal))
    (let ((line (make-line nil nil "")))
      (set-buffer-start-point (make-point buffer 1 line 0 :kind :right-inserting)
                              buffer)
      (set-buffer-end-point (make-point buffer 1 line 0
                                        :kind :left-inserting)
                            buffer)
      (setf (buffer-point buffer)
            (make-point buffer 1 line 0
                        :kind :left-inserting)))
    (unless temporary (add-buffer buffer))
    buffer))

(defun bufferp (x)
  "`x`が`buffer`ならT、それ以外ならNILを返します。"
  (typep x 'buffer))

(defun buffer-modified-p (&optional (buffer (current-buffer)))
  "`buffer`が変更されていたらT、それ以外ならNILを返します。"
  (/= 0 (buffer-%modified-p buffer)))

(defun buffer-enable-undo-p (&optional (buffer (current-buffer)))
  "`buffer`でアンドゥが有効ならT、それ以外ならNILを返します。"
  (buffer-%enable-undo-p buffer))

(defun buffer-enable-undo (buffer)
  "`buffer`のアンドゥを有効にします。"
  (setf (buffer-%enable-undo-p buffer) t)
  nil)

(defun buffer-disable-undo (buffer)
  "`buffer`のアンドゥを無効にしてアンドゥ用の情報を空にします。"
  (setf (buffer-%enable-undo-p buffer) nil)
  (setf (buffer-edit-history buffer) (make-array 0 :adjustable t :fill-pointer 0))
  (setf (buffer-redo-stack buffer) nil)
  nil)

(defmethod print-object ((buffer buffer) stream)
  (format stream "#<BUFFER ~a ~a>"
          (buffer-name buffer)
          (buffer-filename buffer)))

(defun %buffer-clear-keep-binfo (buffer)
  (when (%buffer-keep-binfo buffer)
    (destructuring-bind (view-point point)
        (%buffer-keep-binfo buffer)
      (delete-point view-point)
      (delete-point point))))

(defun buffer-free (buffer)
  (%buffer-clear-keep-binfo buffer)
  (delete-point (buffer-point buffer))
  (setf (buffer-point buffer) nil))

(defun deleted-buffer-p (buffer)
  (null (buffer-point buffer)))

(defun buffer-name (&optional (buffer (current-buffer)))
  "`buffer`の名前を返します。"
  (buffer-%name buffer))

(defun buffer-filename (&optional (buffer (current-buffer)))
  "`buffer`のファイル名を返します。"
  (alexandria:when-let (filename (buffer-%filename buffer))
    (namestring filename)))

(defun (setf buffer-filename) (filename &optional (buffer (current-buffer)))
  (setf (buffer-directory buffer) (directory-namestring filename))
  (setf (buffer-%filename buffer) filename))

(defun buffer-directory (&optional (buffer (current-buffer)))
  "`buffer`のディレクトリを返します。"
  (or (buffer-%directory buffer)
      (namestring (uiop:getcwd))))

(defun (setf buffer-directory) (directory &optional (buffer (current-buffer)))
  (let ((result (uiop:directory-exists-p directory)))
    (unless result
      (error 'directory-does-not-exist :directory directory))
    (setf (buffer-%directory buffer)
          (namestring result))))

(defun buffer-unmark (buffer)
  "`buffer`の変更フラグを下ろします。"
  (setf (buffer-%modified-p buffer) 0))

(defun buffer-mark-cancel (buffer)
  (when (buffer-mark-p buffer)
    (setf (buffer-mark-p buffer) nil)
    t))

(defun check-read-only-buffer (buffer)
  (when (buffer-read-only-p buffer)
    (error 'read-only-error)))

(defun buffer-modify (buffer)
  (ecase *undo-mode*
    ((:edit :redo)
     (incf (buffer-%modified-p buffer)))
    ((:undo)
     (decf (buffer-%modified-p buffer))))
  (buffer-mark-cancel buffer))

(defun push-undo-stack (buffer elt)
  (vector-push-extend elt (buffer-edit-history buffer)))

(defun push-redo-stack (buffer elt)
  (push elt (buffer-redo-stack buffer)))

(defun push-undo (buffer edit)
  (when (buffer-enable-undo-p buffer)
    (ecase *undo-mode*
      (:edit
       (push-undo-stack buffer edit)
       (setf (buffer-redo-stack buffer) nil))
      (:redo
       (push-undo-stack buffer edit))
      (:undo
       (push-redo-stack buffer edit)))))

(defun buffer-rename (buffer name)
  "`buffer`の名前を`name`に変更します。"
  (check-type buffer buffer)
  (check-type name string)
  (when (get-buffer name)
    (editor-error "Buffer name `~A' is in use" name))
  (setf (buffer-%name buffer) name))

(defun buffer-undo-1 (point)
  (let* ((buffer (point-buffer point))
         (edit-history (buffer-edit-history buffer))
         (elt (and (< 0 (length edit-history)) (vector-pop edit-history))))
    (when elt
      (let ((*undo-mode* :undo))
        (unless (eq elt :separator)
          (apply-inverse-edit elt point))))))

(defun buffer-undo (point)
  (let ((buffer (point-buffer point)))
    (push :separator (buffer-redo-stack buffer))
    (when (eq :separator (last-edit-history buffer))
      (vector-pop (buffer-edit-history buffer)))
    (let ((result0 nil))
      (loop :for result := (buffer-undo-1 point)
            :while result
            :do (setf result0 result))
      (unless result0
        (assert (eq :separator (car (buffer-redo-stack buffer))))
        (pop (buffer-redo-stack buffer)))
      result0)))

(defun buffer-redo-1 (point)
  (let* ((buffer (point-buffer point))
         (elt (pop (buffer-redo-stack buffer))))
    (when elt
      (let ((*undo-mode* :redo))
        (unless (eq elt :separator)
          (apply-inverse-edit elt point))))))

(defun buffer-redo (point)
  (let ((buffer (point-buffer point)))
    (vector-push-extend :separator (buffer-edit-history buffer))
    (let ((result0 nil))
      (loop :for result := (buffer-redo-1 point)
            :while result
            :do (setf result0 result))
      (unless result0
        (assert (eq :separator
                    (last-edit-history buffer)))
        (vector-pop (buffer-edit-history buffer)))
      result0)))

(defun buffer-undo-boundary (&optional (buffer (current-buffer)))
  (unless (eq :separator (last-edit-history buffer))
    (vector-push-extend :separator (buffer-edit-history buffer))))

(defun buffer-value (buffer name &optional default)
  "`buffer`のバッファ変数`name`に束縛されている値を返します。  
`buffer`の型は`buffer`または`point`です。  
変数が設定されていない場合は`default`を返します。"
  (setf buffer (ensure-buffer buffer))
  (multiple-value-bind (value foundp)
      (gethash name (buffer-variables buffer))
    (if foundp value default)))

(defun (setf buffer-value) (value buffer name &optional default)
  "`buffer`のバッファ変数`name`に`value`を束縛します。  
`buffer`の型は`buffer`または`point`です。"
  (declare (ignore default))
  (setf buffer (ensure-buffer buffer))
  (setf (gethash name (buffer-variables buffer)) value))

(defun buffer-unbound (buffer name)
  "`buffer`のバッファ変数`name`の束縛を消します。"
  (remhash name (buffer-variables buffer)))

(defun clear-buffer-variables (&key (buffer (current-buffer)))
  "`buffer`に束縛されているすべてのバッファ変数を消します。"
  (clrhash (buffer-variables buffer)))
