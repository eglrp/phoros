;;; PHOROS -- Photogrammetric Road Survey
;;; Copyright (C) 2010, 2011 Bert Burgemeister
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

(defun nuke-all-tables ()
  "Drop all tables (except PostGIS helper tables) and sequences in current database."
  (let ((user-tables (list-tables))
        (sequences (list-sequences))
        (system-tables '(:spatial-ref-sys :geometry-columns)))
    (dolist (system-table system-tables)
      (setf user-tables (remove system-table user-tables))) ; TODO: do we need to spare those?
    (dolist (user-table user-tables)
      (execute (format nil "DROP TABLE IF EXISTS ~A CASCADE" (s-sql:to-sql-name user-table))))
    (dolist (sequence sequences)
      (execute (format nil "DROP SEQUENCE IF EXISTS ~A CASCADE" (s-sql:to-sql-name sequence))))))
 
;;TODO: make a spatial-ref-sys table
;;
;;CREATE TABLE spatial_ref_sys ( 
;;  srid       INTEGER NOT NULL PRIMARY KEY, 
;;  auth_name  VARCHAR(256), 
;;  auth_srid  INTEGER, 
;;  srtext     VARCHAR(2048), 
;;  proj4text  VARCHAR(2048) 
;;)

;;TODO: make a geometry-columns table
;;
;;CREATE TABLE geometry_columns ( 
;;  f_table_catalog    VARRCHAR(256) NOT NULL, 
;;  f_table_schema     VARCHAR(256) NOT NULL,
;;  f_table_nam        VARCHAR(256) NOT NULL, 
;;  f_geometry_column  VARCHAR(256) NOT NULL, 
;;  coord_dimension    INTEGER NOT NULL, 
;;  srid               INTEGER NOT NULL, 
;;  type               VARCHAR(30) NOT NULL 
;;)

(defclass sys-user ()
  ((user-id
    :reader user-id

    :col-type integer
    :col-default (:nextval 'sys-user-id-seq))
   (user-name
    :col-type text
    :initarg :user-name
    :documentation "This one is used for authentication.")
   (user-password
    :writer (setf user-password)
    :col-type text
    :initarg :user-password)
   (user-full-name
    :writer (setf user-full-name)
    :col-type text
    :initarg :user-full-name))
  (:metaclass dao-class)
  (:keys user-id)
  (:documentation "List of users of the presentation front end.  This is certainly not a full-fledged authentication system."))

(deftable sys-user
  (:create-sequence 'sys-user-id-seq)
  (!dao-def))

(defclass sys-acquisition-project ()
  ((acquisition-project-id
    :reader acquisition-project-id
    :col-type integer
    :col-default (:nextval 'sys-acquisition-project-id-seq))
   (common-table-name
    :col-type text
    :initarg :common-table-name
    :documentation "Name of this project's data tables sans their canonical prefixes and suffixes.  Serves as a human-readable acquisition procect identifier.  Should be one table for all projects but this seems to come with a speed penalty."))
  (:metaclass dao-class)
  (:keys acquisition-project-id)
  (:documentation "An acquisition project is basically a set of measurements that is stored in a common table."))

(deftable sys-acquisition-project
  (:create-sequence 'sys-acquisition-project-id-seq)
  (!dao-def)
  (sql-compile
   `(:alter-table ,*table-name* :add :constraint "common-table-name-unique"
                  :unique 'common-table-name)))

(defclass sys-presentation-project ()
  ((presentation-project-id
    :reader presentation-project-id
    :col-type integer
    :col-default (:nextval 'sys-presentation-project-id-seq))
   (presentation-project-name
    :col-type text
    :initarg :presentation-project-name))
  (:metaclass dao-class)
  (:keys presentation-project-name))

(deftable sys-presentation-project
  (:create-sequence 'sys-presentation-project-id-seq)
  (!dao-def)
  (:alter-table sys-presentation-project
                :add :constraint "presentation-project-id-unique"
                :unique 'presentation-project-id))

(defclass sys-user-role ()
  ((user-id
    :initarg :user-id
    :col-type integer)
   (presentation-project-id
    :initarg :presentation-project-id
    :col-type integer)
   (user-role
    :initarg :user-role
    :col-type text
    :documentation "Some well-defined string, e.g. read-only, r/w, etc.  TODO: define some."))
  (:metaclass dao-class)
  (:keys user-id presentation-project-id))

(deftable sys-user-role
  (!dao-def)
  (!foreign 'sys-user 'user-id :on-delete :cascade :on-update :cascade)
  (!foreign 'sys-presentation-project 'presentation-project-id
            :on-delete :cascade :on-update :cascade))

(defclass sys-measurement ()
  ((measurement-id
    :reader measurement-id
    :col-type integer
    :col-default (:nextval 'sys-measurement-id-seq))
   (acquisition-project-id
    :initarg :acquisition-project-id
    :col-type integer)
   (directory
    :initarg :directory
    :col-type text
    :documentation
    "Below some universal root common to all measurements; excluding
`applanix/´ `images/´ etc.

The entire directory structure looks like this:

Points
======
/some/path/in/our/system/this/measurement/blah/applanix/points/xyz-event1.txt
/some/path/in/our/system/this/measurement/blah/applanix/points/uvw-event2.txt
                                          ---- +++++++++++++++ ----+++++ ++++
^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^                               ^
    universal root       stored here in                                event
                         slot directory                                number

Images
======
/some/path/in/our/system/this/measurement/blah/images/front77.pictures
/some/path/in/our/system/this/measurement/blah/images/front78.pictures
                                          ---- ++++++         ++++++++
^^^^^^^^^^^^^^^^^^^^^^^^ ^^^^^^^^^^^^^^^^             ^^^^^^^^^^^^^^^^
    universal root       stored here in               stored file name 
                         slot directory

++++ means constant
---- means unimportant

TODO: /images/ part not currently enforced.")
   (cartesian-system
    :initarg :cartesian-system
    :col-type text
    :documentation
    "Definition (as a Proj.4 string) of the coordinate system the recorded standard deviations are in."))
  (:metaclass dao-class)
  (:keys measurement-id)
  (:documentation "A measurement comprises .pictures files and one set of GPS event log files in a dedicated directory."))

(deftable sys-measurement
  (:create-sequence 'sys-measurement-id-seq)
  (!dao-def)
  (!foreign 'sys-acquisition-project 'acquisition-project-id
            :on-delete :cascade :on-update :cascade))

(defclass sys-presentation ()
  ((presentation-project-id
    :initarg :presentation-project-id
    :col-type integer)
   (measurement-id
    :initarg :measurement-id
    :col-type integer))
  (:metaclass dao-class)
  (:keys presentation-project-id measurement-id)
  (:documentation "Tell us which measurements belong to which presentation project(s)."))

(deftable sys-presentation
  (!dao-def)
  (!foreign 'sys-presentation-project 'presentation-project-id
            :on-delete :cascade :on-update :cascade)
  (!foreign 'sys-measurement 'measurement-id
            :on-delete :cascade :on-update :cascade))

(defclass sys-camera-hardware ()
  ((camera-hardware-id
    :reader camera-hardware-id
    :col-type integer
    :col-default (:nextval 'sys-camera-hardware-id-seq))
   (sensor-width-pix
    :col-type integer)
   (sensor-height-pix
    :col-type integer)
   (pix-size
    :col-type double-float)
   (channels
    :col-type integer)
   (pix-depth
    :col-type integer)
   (color-raiser
    :col-type float[]
    :documentation "Array of multipliers for red, green, blue.")
   (bayer-pattern
    :col-type integer[]
    :documentation "Array containing the colors of the first pixels of the first rows (actually, row, as postmodern can't handle two-dimensional arrays (and if it could, we wouldn't use them anyway)).  Each pixel is to be interpreted as a three-byte RGB value, red in the least-significant byte.")
   (serial-number
    :col-type text)
   (description
    :col-type text
    :description "Camera type, manufacturer, etc."))
  (:metaclass dao-class)
  (:keys camera-hardware-id))

(deftable sys-camera-hardware
  (:create-sequence 'sys-camera-hardware-id-seq)
  (!dao-def))

(defclass sys-lens ()
  ((lens-id
    :reader lens-id
    :col-type integer
    :col-default (:nextval 'sys-lens-id-seq))
   (c
    :col-type double-float
    :documentation "Focal length.  Only for human consumption.")
   (serial-number
    :col-type text)
   (description
    :col-type text
    :documentation "Lens type, manufacturer, etc."))
  (:metaclass dao-class)
  (:keys lens-id))

(deftable sys-lens
  (:create-sequence 'sys-lens-id-seq)
  (!dao-def))

(defclass sys-generic-device ()
  ((generic-device-id
    :reader generic-device-id
    :col-type integer
    :col-default (:nextval 'sys-generic-device-id-seq))
   (camera-hardware-id
    :initarg :camera-hardware-id
    :col-type (or db-null integer))
   (lens-id
    :initarg :lens-id
    :col-type (or db-null integer))
   (scanner-id
    :initarg :scanner-id
    :col-type (or db-null integer)
    :documentation "Scanners yet to be defined."))
  (:metaclass dao-class)
  (:keys generic-device-id)
  (:documentation "A row should describe either a camera with a lens, or a laser scanner."))

(deftable sys-generic-device
  (:create-sequence 'sys-generic-device-id-seq)
  (!dao-def)
  (!foreign 'sys-camera-hardware 'camera-hardware-id
            :on-delete :restrict :on-update :restrict)
  (!foreign 'sys-lens 'lens-id :on-delete :restrict :on-update :restrict)
  ;;;; Once we have a sys-scanner table:
  ;;(!foreign 'sys-scanner 'scanner-id :on-delete :restrict :on-update :restrict)
  )

(defclass sys-device-stage-of-life ()
  ((device-stage-of-life-id
    :reader device-stage-of-life-id
    :col-type integer
    :col-default (:nextval 'sys-device-stage-of-life-seq))
   (recorded-device-id
    :col-type text
    :documentation "Must be stored next to each data record.  Example: in a .pictures file, this is the value of `cam=´.")
   (event-number
    :reader event-number
    :col-type text
    :documentation "Identifier for the GPS event that triggers this device.  Must correspond to the N the GPS file name: ...eventN.txt.")
   (generic-device-id
    :col-type integer)
   (vehicle-name
    :col-type text)
   (casing-name
    :col-type text
    :documentation "Something like `upper rear left´ or maybe `1.2.1´")
   (computer-name
    :col-type text
    :documentation "Computer (or or other recording device) this device is connected to.")
   (computer-interface-name
    :col-type text
    :documentation "Things like `eth0´, `COM1´ etc.")
   (mounting-date
    :col-type :timestamp-with-time-zone)
   (unmounting-date
    :col-type (or db-null :timestamp-with-time-zone)
    :documentation "Date and time when this device was unmounted or altered in other ways that may render the current calibration invalid."))
  (:metaclass dao-class)
  (:keys device-stage-of-life-id)
  (:documentation "This data is to be collected on the measuring vehicle.  There must be a new record for every relevant change (including accidental ones) in device configuration."))

(deftable sys-device-stage-of-life
  (:create-sequence 'sys-device-stage-of-life-seq)
  (!dao-def)
  (!index 'recorded-device-id)
  (!index 'mounting-date)
  (!index 'unmounting-date)
  (!foreign 'sys-generic-device 'generic-device-id
            :on-delete :restrict :on-update :restrict))

(defclass sys-camera-calibration ()
  ((device-stage-of-life-id
    :reader device-stage-of-life-id
    :col-type integer
    :documentation "This tells us what hardware this calibration is for.")
   (date
    :reader date
    :col-type :timestamp-with-time-zone)
   (person
    :col-type text)
   (main-description
    :col-type text
    :documentation "Regarding this entire set of calibration data.  Note the special-purpose description fields inner-orientation-description, outer-orientation-description, boresight-description.")
   (debug
    :col-type boolean
    :documentation "If true: not for production use; may be altered or deleted at any time.")
   (photogrammetry-version
    :col-type text
    :documentation "Software version used to create this data.")
   (mounting-angle
    :col-type integer
    :documentation "Head up = 0; right ear up = 90; left ear up = -90; head down = 180.")
   (inner-orientation-description
    :col-type text
    :documentation "Comments regarding inner orientation calibration.")
   (c
    :col-type double-float
    :documentation "Inner orientation: focal length.")
   (xh
    :col-type double-float
    :documentation "Inner orientation: principal point displacement.")
   (yh
    :col-type double-float
    :documentation "Inner orientation: principal point displacement.")
   (a1
    :col-type double-float
    :documentation "Inner orientation: radial distortion.")
   (a2
    :col-type double-float
    :documentation "Inner orientation: radial distortion.")
   (a3
    :col-type double-float
    :documentation "Inner orientation: radial distortion.")
   (b1
    :col-type double-float
    :documentation "Inner orientation: asymmetric and tangential distortion.")
   (b2
    :col-type double-float
    :documentation "Inner orientation: asymmetric and tangential distortion.")
   (c1
    :col-type double-float
    :documentation "Inner orientation: affinity and shear distortion.")
   (c2
    :col-type double-float
    :documentation "Inner orientation: affinity and shear distortion.")
   (r0
    :col-type double-float
    :documentation "Inner orientation.")
   (outer-orientation-description
    :col-type text
    :documentation "Comments regarding outer orientation calibration.")
   (dx
    :col-type double-float
    :documentation "Outer orientation; in metres.")
   (dy
    :col-type double-float
    :documentation "Outer orientation; in metres.")
   (dz
    :col-type double-float
    :documentation "Outer orientation; in metres.")
   (omega
    :col-type double-float
    :documentation "Outer orientation.")
   (phi
    :col-type double-float
    :documentation "Outer orientation.")
   (kappa
    :col-type double-float
    :documentation "Outer orientation.")
   (boresight-description
    :col-type text
    :documentation "Comments regarding boresight alignment calibration.")
   (b-dx
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-dy
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-dz
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-ddx
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-ddy
    :col-type double-float
    :Documentation "Boresight alignment.")
   (b-ddz
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-rotx
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-roty
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-rotz
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-drotx
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-droty
    :col-type double-float
    :documentation "Boresight alignment.")
   (b-drotz
    :col-type double-float
    :documentation "Boresight alignment.")
   (nx
    :col-type double-float
    :documentation "Component of unit vector of vehicle ground plane.")
   (ny
    :col-type double-float
    :documentation "Component of unit vector of vehicle ground plane.")
   (nz
    :col-type double-float
    :documentation "Component of unit vector of vehicle ground plane.")
   (d
    :col-type double-float
    :documentation "Distance of vehicle ground plane."))
  (:metaclass dao-class)
  (:keys device-stage-of-life-id date)
  (:documentation "Camera calibration parameters."))

(deftable sys-camera-calibration
  (!dao-def)
  (!foreign 'sys-device-stage-of-life 'device-stage-of-life-id
            :on-delete :restrict :on-update :restrict))

(defun phoros-db-major-version ()
  "Get the version number of the database structure we are currently
connected to.  It is supposed to be equal to the :major part of
phoros-version."
  (query
   (:select 'last-value :from 'sys-phoros-major-version)
   :single!))

(defun (setf phoros-db-major-version) (major-version)
  "Set the version number of the database structure we are currently
connected to. This can only be done once per database."
  (execute
   (:create-sequence 'sys-phoros-major-version :min-value -1 :max-value major-version :start major-version))
  (phoros-db-major-version))

(defun assert-phoros-db-major-version ()
  "Check if phoros version and version of the database we are connected to match."
  (assert (= (phoros-db-major-version) (phoros-version :major t)) ()
          "Can't use a Phoros database structure of version ~D.  It should be version ~D.  Either create a new database structure using this version of Phoros, or use Phoros version ~2:*~D.x.x."
          (phoros-db-major-version) (phoros-version :major t)))

(defun create-sys-tables ()
  "Create in current database a set of sys-* tables, i.e. tables that
are used by all projects.  The database should probably be empty."
  (setf (phoros-db-major-version) (phoros-version :major t))
  (create-table 'sys-user)
  (create-table 'sys-acquisition-project)
  (create-table 'sys-presentation-project)
  (create-table 'sys-user-role)
  (create-table 'sys-measurement)
  (create-table 'sys-presentation)
  (create-table 'sys-camera-hardware)
  (create-table 'sys-lens)
  (create-table 'sys-generic-device)
  (create-table 'sys-device-stage-of-life)
  (create-table 'sys-camera-calibration))

(defun !!index (table field &key (index-type :btree)) 
  (format nil "CREATE INDEX ~0@*~A_~1@*~A_index ON ~0@*~A USING ~2@*~A (~1@*~A)"
          (s-sql:to-sql-name table)
          (s-sql:to-sql-name field)
          (s-sql:to-sql-name index-type)))

(defclass point-template ()
  (;; We need a slot point-id which is defined in our subclasses.
   (measurement-id
    :writer (setf measurement-id)
    :col-type integer)
   (event-number
    :documentation "Event that triggered this record.  Taken from the GPS file name: ...eventN.txt gives an event number N.  May be a string of any length.")
   (gps-time
    :reader gps-time
    :documentation "UTC calculated from GPS week time.")
   (trigger-time
    :writer (setf trigger-time)
    :col-type double-precision
    :documentation "Time in seconds from 1900.  Values before 1980-01-06T00:00:00Z are considered invalid.")
   (roll
    :col-type double-precision)
   (pitch
    :col-type double-precision)
   (heading
    :col-type double-precision)
   (east-velocity
    :col-type double-precision)
   (north-velocity
    :col-type double-precision)
   (up-velocity
    :col-type double-precision)
   (east-sd
    :col-type double-precision)
   (north-sd
    :col-type double-precision)
   (height-sd
    :col-type double-precision)
   (roll-sd
    :col-type double-precision)
   (pitch-sd
    :col-type double-precision)
   (heading-sd
    :col-type double-precision)
   (longitude
    :reader longitude
    :documentation "Same content as in slot coordinates.  TODO: should probably be made redundant in favour of the latter.")
   (latitude
    :reader latitude
    :documentation "Same content as in slot coordinates.  TODO: should probably be made redundant in favour of the latter.")
   (ellipsoid-height
    :reader ellipsoid-height
    :documentation "Same content as in slot coordinates.  TODO: should probably be made redundant in favour of the latter.")
   (coordinates
    :col-type (or db-null geometry)
    :documentation "Geographic coordinates.")
   (easting
    :reader easting
    :documentation "In the same coordinate system as the standard deviations.")
   (northing
    :reader northing
    :documentation "In the same coordinate system as the standard deviations.")
   (cartesian-height
    :reader cartesian-height
    :documentation "In the same coordinate system as the standard deviations."))
  (:metaclass dao-class)
  (:keys point-id)
  (:documentation "Information about one GPS point, originally from applanix/**/*event*.txt.  There shouldn't be any point-id without a matching one in the *-image table.  This can't be enforced on database level.  Perhaps we should create some cleaning operation to maintain referential integrity. (TODO)"))

(defclass image-template ()
  ((measurement-id
    :writer (setf measurement-id)
    :col-type integer
    :documentation "A primary key.  We need to recognize images should they come in twice, perhaps with slightly changed point data.  In such a case we want the old ones superseded.")
   (filename
    :reader filename
    :initarg :filename
    :col-type text
    :documentation "Name without any directory components.")
   (byte-position
    :reader image-byte-position
    :initarg :byte-position
    :col-type integer
    :documentation "Start of image in .pictures file named by slot filename.")
   (point-id
    :accessor point-id
    :col-type integer)
   (recorded-device-id
    :initarg :recorded-device-id
    :reader recorded-device-id
    :col-type text
    :documentation "As found in .pictures file, header tag `cam=´.")
   ;;(footprint
   ;; :col-type (or db-null geometry)
   ;; :documentation "Polygon on the ground describing the approximate area covered by this image.")
   (gain
    :initarg :gain
    :col-type double-precision
    :documentation "Camera parameter. TODO: needs a decent definition")
   (shutter
    :initarg :shutter
    :col-type double-precision
    :documentation "Camera parameter. TODO: needs a decent definition")
   (trigger-time
    :initarg :trigger-time
    :accessor trigger-time
    :documentation "Time in seconds from 1900-01-01.")
   (fake-trigger-time-p
    :accessor fake-trigger-time-p
    :initform nil
    :documentation "T if trigger-time has been reconstructed from adjacent data.")
   (camera-timestamp
    :initarg :camera-timestamp
    :reader camera-timestamp
    :documentation "Some camera clocktick count starting at an unknown origin."))
  (:metaclass dao-class)
  (:keys measurement-id filename byte-position)
  (:documentation "One row per image, originating from a .pictures file."))

;;(defclass aggregate-template ()
;;  ((date                                ;TODO: debug only
;;    :col-type :timestamp-with-time-zone)
;;   (measurement-id                      ;TODO: debug only
;;    :col-type integer)
;;   (recorded-device-id                  ;TODO: debug only
;;    :col-type integer)
;;   (device-stage-of-life-id             ;TODO: debug only
;;    :col-type integer)
;;   (filename
;;    :col-type string)
;;   (byte-position
;;    :col-type integer)
;;   (point-id
;;    :col-type integer)
;;   (trigger-time
;;    :col-type double-precision)
;;   (longitude
;;    :col-type double-precision)
;;   (latitude
;;    :col-type double-precision)
;;   (ellipsoid-height
;;    :col-type double-precision)
;;   (east-sd
;;    :col-type double-precision)
;;   (north-sd
;;    :col-type double-precision)
;;   (height-sd
;;    :col-type double-precision)
;;   (roll
;;    :col-type double-precision)
;;   (pitch
;;    :col-type double-precision)
;;   (heading
;;    :col-type double-precision)
;;   (roll-sd
;;    :col-type double-precision)
;;   (pitch-sd
;;    :col-type double-precision)
;;   (heading-sd
;;    :col-type double-precision)
;;   (sensor-width-pix
;;    :col-type double-precision)
;;   (sensor-height-pix
;;    :col-type double-precision)
;;   (pix-size
;;    :col-type double-precision)
;;   (mounting-angle
;;    :col-type integer)
;;   (dx
;;    :col-type double-precision)
;;   (dy
;;    :col-type double-precision)
;;   (dz
;;    :col-type double-precision)
;;   (omega
;;    :col-type double-precision)
;;   (phi
;;    :col-type double-precision)
;;   (kappa
;;    :col-type double-precision)
;;   (c
;;    :col-type double-precision)
;;   (xh
;;    :col-type double-precision)
;;   (yh
;;    :col-type double-precision)
;;   (a1
;;    :col-type double-precision)
;;   (a2
;;    :col-type double-precision)
;;   (a3
;;    :col-type double-precision)
;;   (b1
;;    :col-type double-precision)
;;   (b2
;;    :col-type double-precision)
;;   (c1
;;    :col-type double-precision)
;;   (c2
;;    :col-type double-precision)
;;   (r0
;;    :col-type double-precision)
;;   (b-dx
;;    :col-type double-precision)
;;   (b-dy
;;    :col-type double-precision)
;;   (b-dz
;;    :col-type double-precision)
;;   (b-rotx
;;    :col-type double-precision)
;;   (b-roty
;;    :col-type double-precision)
;;   (b-rotz
;;    :col-type double-precision))
;;  (:metaclass dao-class)
;;  (:documentation
;;   "Representation of a view into all relevant data for one image.  TODO: use mixins to avoid repetition."))

(defclass user-point-template ()
  (;; We need a slot user-point-id which is defined in our subclasses.
   (user-id
    :initarg :user-id
    :col-type integer
    :documentation "User who stored this point.")
   (attribute
    :initarg :attribute
    :col-type text
    :documentation "Class of this user point.")
   (description
    :initarg :description
    :col-type text
    :documentation "User comment regarding this point.")
   (numeric-description
    :initarg :numeric-description
    :col-type text
    :documentation "User-generated point id regarding this point.")
   (creation-date
    :col-type :timestamp-with-time-zone
    :documentation "Creation time of this point.")
   (coordinates
    :col-type (or db-null geometry)
    :documentation "Geographic coordinates.")
   (stdx-global
    :initarg :stdx-global
    :col-type double-precision
    :documentation "Component of standard deviation, in metres.")
   (stdy-global
    :initarg :stdy-global
    :col-type double-precision
    :documentation "Component of standard deviation, in metres.")
   (stdz-global
    :initarg :stdz-global
    :col-type double-precision
    :documentation "Component of standard deviation, in metres."))
  (:metaclass dao-class)
  (:keys user-point-id)
  (:documentation "Points defined by users."))

(defclass point-data (point-template)
  ((point-id
    :accessor point-id
    :initform nil
    :col-type integer
    :col-default nil)                   ;to be redefined
   point-id-sequence-name)              ;to be redefined
  (:metaclass dao-class)
  (:table-name nil))                    ;to be redefined

(defclass image-data (image-template)
  ()
  (:metaclass dao-class)
  (:table-name nil))                    ;to be redefined

;;(defclass aggregate-data (aggregate-template)
;;  ()
;;  (:metaclass dao-class)
;;  (:table-name nil))                    ;to be redefined

(defclass user-point-data (user-point-template)
  ((user-point-id
    :accessor user-point-id
    :initform nil
    :col-type integer
    :col-default nil)                   ;to be redefined
   user-point-id-sequence-name)         ;to be redefined)
  (:metaclass dao-class)
  (:table-name nil))                    ;to be redefined

(let ((table-prefix "dat-"))
  (defun point-data-table-name (common-table-name)
    (make-symbol (format nil "~A~A-point" table-prefix common-table-name)))

  (defun image-data-table-name (common-table-name)
    (make-symbol (format nil "~A~A-image" table-prefix common-table-name)))

  (defun point-id-seq-name (common-table-name)
    (make-symbol (format nil "~A~A-point-id-seq" table-prefix common-table-name)))

  (defun aggregate-view-name (common-table-name)
    (make-symbol (format nil "~A~A-aggregate" table-prefix common-table-name))))

(let ((table-prefix "usr-"))
  (defun user-point-table-name (presentation-project-name)
    (make-symbol (format nil "~A~A-point" table-prefix presentation-project-name)))

  (defun user-point-id-seq-name (presentation-project-name)
    (make-symbol (format nil "~A~A-point-id-seq" table-prefix presentation-project-name))))

(defun create-data-table-definitions (common-table-name)
  "Define or redefine a bunch of dao-classes which can hold measuring
data and which are connected to database tables named
common-table-name plus type-specific prefix and suffix."
  (let ((image-data-table-name (image-data-table-name common-table-name))
        (point-data-table-name (point-data-table-name common-table-name))
        (point-id-sequence-name (point-id-seq-name common-table-name)))
    (eval
     `(defclass point-data (point-template)
        ((point-id
          :accessor point-id
          :initform nil
          :col-type integer
          :col-default (:nextval ,point-id-sequence-name)) ; redefinition
         (point-id-sequence-name
          :initform ,(string point-id-sequence-name) ; redefinition
          :reader point-id-sequence-name
          :allocation :class))
        (:metaclass dao-class)
        (:table-name ,point-data-table-name))) ;redefinition
    (deftable point-data
      (:create-sequence point-id-sequence-name)
      (!dao-def)
      (!!index point-data-table-name 'measurement-id)
      (!!index point-data-table-name 'trigger-time)
      (!!index point-data-table-name 'coordinates :index-type :gist)
      ;; The following let shouldn't be necessary. (Wart In !foreign.)
      (let ((*table-symbol* point-data-table-name)
            (*table-name*  (s-sql:to-sql-name point-data-table-name)))
        (!foreign 'sys-measurement 'measurement-id
                  :on-delete :cascade :on-update :cascade)))
    (eval
     `(defclass image-data (image-template)
        ()
        (:metaclass dao-class)
        (:table-name ,image-data-table-name))) ; redefintion
    (deftable image-data
      (!dao-def)
      (!!index image-data-table-name 'measurement-id)
      (!!index image-data-table-name 'recorded-device-id)
      (!!index image-data-table-name 'gain)
      (!!index image-data-table-name 'shutter)
      ;;TODO: disabled as we don't have footprints: (!!index image-data-table-name 'footprint :index-type :gist)
      ;; The following let shouldn't be necessary. (Wart in !foreign.)
      (let ((*table-symbol* image-data-table-name)
            (*table-name*  (s-sql:to-sql-name image-data-table-name)))
        (!foreign point-data-table-name 'point-id
                  :on-delete :cascade :on-update :cascade)
        (!foreign 'sys-measurement 'measurement-id
                  :on-delete :cascade :on-update :cascade)))))

(defun create-user-table-definition (presentation-project-name)
  "Define or redefine a dao-class which can hold user points and which
is connected to a database table named presentation-project-name plus
type-specific prefix and suffix."
  (let ((user-point-table-name (user-point-table-name presentation-project-name))
        (user-point-id-sequence-name (user-point-id-seq-name presentation-project-name)))
    (eval
     `(defclass user-point (user-point-template)
        ((user-point-id
          :accessor point-id
          :initform nil
          :col-type integer
          :col-default (:nextval ,user-point-id-sequence-name))) ; redefinition
        (:metaclass dao-class)
        (:table-name ,user-point-table-name))) ;redefinition
    (deftable user-point
      (:create-sequence user-point-id-sequence-name)
      (!dao-def)
      (!!index user-point-table-name 'coordinates :index-type :gist))))

(defun create-aggregate-view (common-table-name)
  "Create a view of a set of measuring and calibration data
belonging to images."
  (let ((image-data-table-name (image-data-table-name common-table-name))
        (point-data-table-name (point-data-table-name common-table-name))
        (aggregate-view-name (aggregate-view-name common-table-name)))
    (eval
     `(execute
       (:create-view
        ,aggregate-view-name
        (:select
         'presentation-project-id
         'date                          ;TODO: debug only
         (:dot ',point-data-table-name 'measurement-id) (:dot ',image-data-table-name 'recorded-device-id) 'sys-camera-calibration.device-stage-of-life-id ;TODO: debug only
         'directory
         'filename 'byte-position (:dot ',point-data-table-name 'point-id)
         'trigger-time
         'coordinates                   ;the search target
         (:as (:st_x (:st_transform 'coordinates *standard-coordinates*)) 'longitude)
         (:as (:st_y (:st_transform 'coordinates *standard-coordinates*)) 'latitude)
         (:as (:st_z (:st_transform 'coordinates *standard-coordinates*)) 'ellipsoid-height)
         'cartesian-system
         'east-sd 'north-sd 'height-sd
         'roll 'pitch 'heading 'roll-sd 'pitch-sd 'heading-sd
         'sensor-width-pix 'sensor-height-pix 'pix-size
         'mounting-angle
         'dx 'dy 'dz 'omega 'phi 'kappa
         'c 'xh 'yh 'a1 'a2 'a3 'b1 'b2 'c1 'c2 'r0
         'b-dx 'b-dy 'b-dz 'b-rotx 'b-roty 'b-rotz
         'b-ddx 'b-ddy 'b-ddz 'b-drotx 'b-droty 'b-drotz
         :from
         'sys-measurement
         'sys-presentation
         ',point-data-table-name ',image-data-table-name
         'sys-device-stage-of-life 'sys-generic-device 'sys-camera-hardware
         'sys-camera-calibration
         :where (:and (:= (:dot ',image-data-table-name 'measurement-id) 'sys-presentation.measurement-id)
                      (:= 'sys-presentation.measurement-id 'sys-measurement.measurement-id)
                      (:= (:dot ',point-data-table-name 'point-id) (:dot ',image-data-table-name 'point-id))
                      (:= (:dot ',image-data-table-name 'recorded-device-id) 'sys-device-stage-of-life.recorded-device-id)
                      (:= 'sys-generic-device.generic-device-id 'sys-device-stage-of-life.generic-device-id)
                      (:= 'sys-camera-hardware.camera-hardware-id 'sys-generic-device.camera-hardware-id)
                      (:= 'sys-device-stage-of-life.device-stage-of-life-id 'sys-camera-calibration.device-stage-of-life-id)
                      (:= 'sys-device-stage-of-life.device-stage-of-life-id 
                          (:limit (:order-by (:select 'sys-camera-calibration.device-stage-of-life-id :from 'sys-camera-calibration
                                                      :where (:= 'sys-device-stage-of-life.device-stage-of-life-id 'sys-camera-calibration.device-stage-of-life-id))
                                             (:desc 'date))
                                  1))
                      (:<= (:extract :epoch 'sys-device-stage-of-life.mounting-date) (:dot ',point-data-table-name 'trigger-time))
                      (:or (:is-null 'sys-device-stage-of-life.unmounting-date)
                           (:>= (:extract :epoch 'sys-device-stage-of-life.mounting-date) (:dot ',point-data-table-name 'trigger-time))))))))
    ;;(eval
    ;; `(defclass ,aggregate-view-name (aggregate-data)
    ;;    ()
    ;;    (:metaclass dao-class)
    ;;    (:table-name ,aggregate-view-name))) ;redefinition
    ))

(defun create-acquisition-project (common-table-name)
  "Create in current database a fresh set of canonically named tables.
common-table-name should in most cases resemble the project name and
will be stored in table sys-acquisition-project, field
common-table-name."
  (create-data-table-definitions common-table-name)
  (handler-case (create-sys-tables) ;Create system tables if necessary.
    (cl-postgres-error:syntax-error-or-access-violation () nil))
  (assert-phoros-db-major-version)
  (when (select-dao 'sys-acquisition-project (:= 'common-table-name
                                                 (s-sql:to-sql-name common-table-name)))
    (error "There is already a row with a common-table-name of ~A in table ~A."
           common-table-name
           (s-sql:to-sql-name (dao-table-name 'sys-acquisition-project))))
  (create-table 'point-data)
  (create-table 'image-data)
  (create-aggregate-view common-table-name)
  (insert-dao
   (make-instance 'sys-acquisition-project
                  :common-table-name common-table-name)))

(defun delete-acquisition-project (common-table-name)
  "Delete the acquisition project that uses common-table-name.  Return
nil if there wasn't any."
  (assert-phoros-db-major-version)
  (let ((project
         (car (select-dao 'sys-acquisition-project
                          (:= 'common-table-name common-table-name)))))
    (when project
      (delete-dao project)
      (execute (:drop-view :if-exists (aggregate-view-name common-table-name)))
      (execute (:drop-table :if-exists (image-data-table-name common-table-name)))
      (execute (:drop-table :if-exists (point-data-table-name common-table-name)))
      (execute (:drop-sequence :if-exists (point-id-seq-name common-table-name))))))

(defun delete-measurement (measurement-id)
  "Delete measurement with measurement-id if any; return nil if not."
  (assert-phoros-db-major-version)
  (let ((measurement (get-dao 'sys-measurement measurement-id)))
    (when measurement (delete-dao measurement))))

(defun create-presentation-project (project-name)
  "Create a fresh presentation project in current database.  Return
dao if one was created, or nil if it existed already."
  (assert-phoros-db-major-version)
  (unless (get-dao 'sys-presentation-project project-name)
    (create-user-table-definition project-name)
    (create-table 'user-point)
    (insert-dao (make-instance 'sys-presentation-project
                               :presentation-project-name project-name))))

(defun delete-presentation-project (project-name)
  "Delete the presentation project project-name.  Return nil if there
wasn't any."
  (assert-phoros-db-major-version)
  (let ((project (get-dao 'sys-presentation-project project-name)))
    (when project
      (delete-dao project)
      (execute
       (:drop-table :if-exists (user-point-table-name project-name)))
      (execute
       (:drop-sequence :if-exists (user-point-id-seq-name project-name))))))

(defun create-user (name &key
                    (password (error "password needed."))
                    (full-name (error "full-name needed."))
                    (user-role "read")
                    presentation-projects)
  "Create a fresh user entry or update an existing one with matching
name.  Assign it presentation-projects, deleting any previously
existing assignments."
  (assert-phoros-db-major-version)
  (assert (or (string-equal "read" user-role)
              (string-equal "write" user-role)
              (string-equal "admin" user-role))
          (user-role)
          "~A is not a valid user-role." user-role)
  (let ((user (or (car (select-dao 'sys-user (:= 'user-name name)))                  
                  (make-instance 'sys-user :user-name name)))
        fresh-user-p)
    (setf (user-password user) password
          (user-full-name user) full-name)
    (setf fresh-user-p (save-dao user))
    (mapcar #'delete-dao (select-dao 'sys-user-role
                                     (:= 'user-id (user-id user))))
    (dolist (presentation-project-name presentation-projects)
      (let ((presentation-project
             (get-dao 'sys-presentation-project presentation-project-name)))
        (if presentation-project
            (insert-dao
             (make-instance
              'sys-user-role
              :user-id (user-id user)
              :presentation-project-id
              (presentation-project-id presentation-project)
              :user-role (string-downcase user-role))) ;TODO: we should be able to set role per presentation-project.
            (warn
             "There is no presentation project ~A" presentation-project-name))))
    fresh-user-p))

(defun delete-user (user-name)
  "Delete user user-name if any; return nil if not."
  (assert-phoros-db-major-version)
  (let ((user (car (select-dao 'sys-user (:= 'user-name user-name)))))
    (when user (delete-dao user))))

(defun add-to-presentation-project (presentation-project-name
                                    &key measurement-ids acquisition-project)
  "Add to presentation project presentation-project-name either a list
of measurements (with measurement-id) or all measurements currently in
acquisition-project (denoted by its common-table-name)."
  (assert-phoros-db-major-version)
  (let* ((presentation-project
          (car (select-dao 'sys-presentation-project
                           (:= 'presentation-project-name
                               presentation-project-name))))
         (presentation-project-id
          (presentation-project-id presentation-project)))
    (flet ((add-measurement (measurement-id)
             "Add one measurement to the given presentation-project."
             (unless (get-dao 'sys-presentation
                              presentation-project-id
                              measurement-id)
               (insert-dao
                (make-instance 'sys-presentation
                               :presentation-project-id presentation-project-id
                               :measurement-id measurement-id)))))
      (cond (measurement-ids (mapc #'add-measurement measurement-ids))
            (acquisition-project
             (dolist
                 (measurement-id
                   (query
                    (:select
                     'measurement-id
                     :from 'sys-measurement 'sys-acquisition-project
                     :where (:and
                             (:= 'sys-acquisition-project.common-table-name
                                 acquisition-project)
                             (:= 'sys-measurement.acquisition-project-id
                                 'sys-acquisition-project.acquisition-project-id)))
                    :column))
               (add-measurement measurement-id)))
            (t (error
                "Don't know what to add.  Need either measurement-id or acquisition-project."))))))

(defun remove-from-presentation-project (presentation-project-name
                                         &key measurement-ids acquisition-project)
  "Remove from presentation project presentation-project-name either a
list of measurements (with measurement-id) or all measurements
currently in acquisition-project with (denoted by its common-table-name).  Return
nil if there weren't anything to remove."
  (assert-phoros-db-major-version)
  (let* ((presentation-project
          (car (select-dao 'sys-presentation-project
                           (:= 'presentation-project-name
                               presentation-project-name))))
         (presentation-project-id
          (Presentation-project-id presentation-project)))
    (flet ((remove-measurement (measurement-id)
             (let ((measurement
                    (car (select-dao
                          'sys-presentation
                          (:and (:= 'measurement-id measurement-id)
                                (:= 'presentation-project-id
                                    presentation-project-id))))))
               (when measurement (delete-dao measurement)))))
    (cond (measurement-ids (mapc #'remove-measurement measurement-ids))
          (acquisition-project
           (dolist
               (measurement-id
                 (query
                  (:select
                   'measurement-id
                   :from 'sys-measurement 'sys-acquisition-project
                   :where (:and
                           (:= 'sys-acquisition-project.common-table-name
                               acquisition-project)
                           (:= 'sys-measurement.acquisition-project-id
                               'sys-acquisition-project.acquisition-project-id)))
                  :column))
             (remove-measurement measurement-id)))
          (t (error
              "Don't know what to remove.  Need either measurement-id or acquisition-project."))))))
           
           
