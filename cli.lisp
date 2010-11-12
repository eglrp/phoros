(in-package :phoros)

(defparameter *opt-spec*
 '((("all" #\a) :type boolean :documentation "do it all")
   ("blah" :type string :initial-value "blob" :documentation "This is a very long multi line documentation. The function SHOW-OPTION-HELP should display this properly indented, that is all lines should start at the same column.")
   ("check-db" :action #'check-database-connection :documentation "Check usability of database connection and exit."
   (("help" #\h) :action #'cli-help :documentation "Display this help and exit.")
   (("version") :action #'cli-version :documentation "Output version information and exit."))))

(defun main ()
  "The UNIX command line entry point."
  (let ((arglist
         (command-line-arguments:handle-command-line *opt-spec* #'list)))))

(defun cli-help (&rest rest)
  "Print --help message."
  (declare (ignore rest))
  (format *standard-output* "~&Usage: ...~&~A"
          (asdf:system-long-description (asdf:find-system :phoros)))
  (command-line-arguments:show-option-help *opt-spec*))

(defun cli-version (&rest rest)
  "Print --version message."
  (declare (ignore rest))
  (format *standard-output* "~&~A ~A~&"
          (asdf:system-description (asdf:find-system :phoros))
          (asdf:component-version (asdf:find-system :phoros))))

(defun check-database-connection (&rest rest)
  (declare (ignore rest))
  )