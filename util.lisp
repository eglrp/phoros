;;; PHOROS -- Photogrammetric Road Survey
;;; Copyright (C) 2011, 2012 Bert Burgemeister
;;;
;;; This program is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 2 of the License, or
;;; (at your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License along
;;; with this program; if not, write to the Free Software Foundation, Inc.,
;;; 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


(in-package :phoros)

(defmacro defun* (name lambda-list &body body)
  "Like defun, define a function, but with an additional lambda list
keyword &mandatory-key which goes after the &key section or in place
of it.  &mandatory-key argument definitions are plain symbols (no
lists).  An error is signalled on function calls where one of those
keyargs is missing."
  (let ((mandatory-key-position (position '&mandatory-key lambda-list))
        (after-key-position (or (position '&allow-other-keys lambda-list)
                                (position '&aux lambda-list))))
    (when mandatory-key-position
      (setf lambda-list
            (append (subseq lambda-list 0 mandatory-key-position)
                    (unless (position '&key lambda-list)
                      '(&key))
                    (mapcar
                     #'(lambda (k)
                         `(,k (error ,(format nil "~A: argument ~A undefined"
                                              name k))))
                     (subseq lambda-list
                             (1+ mandatory-key-position)
                             after-key-position))
                    (when after-key-position
                      (subseq lambda-list after-key-position))))))
  `(defun ,name ,lambda-list ,@body))

(defmacro logged-query (message-tag &rest args)
  "Act like postmodern:query; additionally log some debug information
tagged by the short string message-tag."
  (cl-utilities:with-unique-names
      (executed-query query-milliseconds query-result)
    `(let* (,executed-query
            ,query-milliseconds
            ,query-result
            (cl-postgres:*query-callback*
             #'(lambda (query-string clock-ticks)
                 (setf ,query-milliseconds clock-ticks)
                 (setf ,executed-query query-string))))
       (prog1
           (setf ,query-result
                 (etypecase (car ',args)
                   (list
                    (typecase (caar ',args)
                      (keyword          ;s-sql form
                       (query (sql-compile ',(car args))
                              ,@(cdr args)))
                      (t       ;function (supposedly) returning string
                       (query ,@args))))
                   (string
                    (query ,@args))
                   (symbol
                    (query ,@args))))
         (cl-log:log-message
          :sql
          "[~A] Query ~S~& took ~F seconds and yielded~& ~A."
          ,message-tag
          ,executed-query
          (/ ,query-milliseconds 1000)
          ,query-result)))))

(defmacro cli:with-options ((&key log database aux-database tolerate-missing)
                            (&rest options)
                            &body body
                            &aux postgresql-credentials)
  "Evaluate body with options bound to the values of the respective
command line arguments.  Signal error if tolerate-missing is nil and a
command line argument doesn't have a value.  Elements of options may
be symbols named according to the :long-name argument of the option,
or lists shaped like (symbol) which bind symbol to a list of values
collected for multiple occurence of that option.  If log is t, start
logging first.  If database or aux-database are t, evaluate body with
the appropriate database connection(s) and bind the following
additional variables to the values of the respective command line
arguments: host, port, database, user, password, use-ssl; and/or
aux-host, aux-port, aux-database, aux-user, aux-password,
aux-use-ssl."
  (assert (not (and database aux-database)) ()
          "Can't handle connection to both database and aux-database ~
          at the same time.")
  (when database
    (setf options
          (append options '(host port database user password use-ssl)))
    (setf postgresql-credentials
          '(list database user password host :port port
            :use-ssl (s-sql:from-sql-name use-ssl))))
  (when aux-database
    (setf options
          (append options '(aux-host aux-port aux-database
                            aux-user aux-password aux-use-ssl)))
    (setf postgresql-credentials
          '(list aux-database aux-user aux-password aux-host :port aux-port
            :use-ssl (s-sql:from-sql-name aux-use-ssl))))
  (when log (setf options (append options '(log-dir))))
  (let* ((db-connected-body
          (if (or database aux-database)
              `((with-connection ,postgresql-credentials
                  (muffle-postgresql-warnings)
                  ,@body))
              body))
         (logged-body
          (if log
              `((launch-logger log-dir)
                ,@db-connected-body)
              db-connected-body)))
    `(cli:with-context (cli:make-context)
       (let (,@(loop
                  for option in (remove-duplicates options)
                  if (symbolp option) collect
                    (list option
                          (if tolerate-missing
                              `(cli:getopt :long-name ,(string-downcase option))
                              `(cli:getopt-mandatory ,(string-downcase option))))
                  else collect
                  `(,(car option)
                     (loop
                        for i = ,(if tolerate-missing
                                     `(cli:getopt :long-name ,(string-downcase
                                                               (car option)))
                                     `(cli:getopt-mandatory ,(string-downcase
                                                            (car option))))
                        then (cli:getopt :long-name ,(string-downcase
                                                      (car option)))
                        while i collect i))))
         ,@logged-body))))

(defmacro cli:first-action-option (&rest options)
  "Run action called <option>-action for the first non-nil option;
return its value."
  `(cli:with-context (cli:make-context)
     (loop
        for option in ',options
        when (cli:getopt :long-name (string-downcase option))
        return (funcall (symbol-function (intern (concatenate 'string
                                                              (string option)
                                                              "-ACTION")
                                                 :cli))))))