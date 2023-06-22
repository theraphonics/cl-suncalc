(defpackage :cl-suncalc
  (:use #:common-lisp)
  (:import-from :local-time
                #:encode-universal-time
                #:now))

(in-package :cl-suncalc)

#|
The javascript implementation defined these:
var PI   = Math.PI,
    sin  = Math.sin,
    cos  = Math.cos,
    tan  = Math.tan,
    asin = Math.asin,
    atan = Math.atan2,
    acos = Math.acos,
but since they are available in the CLOS standard i have not.
|#

(defconstant +rad+ (/ pi 180))

; sun calculations are based on http://aa.quae.nl/en/reken/zonpositie.html formulas
; date/time constants and conversions

(defconstant +day-ms+ (* (* (* 1000 60) 60) 24))
(defconstant +j1970+ 2440588)
(defconstant +j2000+ 2451545)

; Helper functions. JavaScript uses unix epoch while Lisp does whatever it wants
; so these are to standardize the dates

(defconstant +suncalc-epoch+ (encode-universal-time 0 0 0 1 1 1970 0))

(defun to-julian (date)
  (/ (- (local-time:timestamp-to-universal (local-time:now)) +suncalc-epoch+)
    (- +day-ms+ (+ 0.5 +j1970+))))

(defun from-julian (j)
  (print j))

(defun to-days (date)
  `(- (to-julian ,date) +j2000+))

; to julian
;from julian

; general calculations for position
(defconstant +e+ (* +rad+ 23.4397))

(defun right-ascension (l b)
  (atan (- (* (sin l) (cos +e+))
    (* (tan b) (sin +e+))) (cos l)))

(defun declination (l b)
  (asin (+ (* (sin b) (cos +e+))
    (* (cos b) (sin +e+) (sin l)))))

(defun azimuth (h phi dec)
  (atan (sin h) (- (* (cos h)
    (sin phi)) (* (tan dec) (cos phi)))))

(defun altitude (h phi dec)
  (asin (+ (* (sin phi) (sin dec))
    (* (cos phi) (cos dec) (cos h)))))

(defun sidereal-time (d lw)
  (- (* +rad+ (+ 280.16 (* 360.9856235 d))) lw))

(defun astro-refraction (h)
  (if (< h 0) ; the following formula works for positive altitudes only.
    (setq h 0) ; if h = -0.08901179 a div/0 would occur.
      ; formula 16.4 of "Astronomical Algorithms" 2nd edition by Jean Meeus (Willmann-Bell, Richmond) 1998.
      ; 1.02 / tan(h + 10.26 / (h + 5.10)) h in degrees, result in arc minutes -> converted to rad:
  (/ 0.002967 (tan (/ (+ h 0.00312536) (+ h 0.08901179))))))

(defun solar-mean-anomaly (d)
  (* +rad+ (+ 357.5291 (* 0.98560028 d))))

(defun ecliptic-longitude (m)
  (let* ((c (* +rad+ (+ (* 1.9148 (sin m)) (* 0.02 (sin (* 2 m))) (* 0.0003 (sin (* 3 m))))))
        (p (* +rad+ 102.9372)))
        (+ (+ m c) (+ p pi))))

(defstruct coordinates
  right-ascension
  declination
  distance
  )

(defun sun-coords (d)
  (let* ((m (solar-mean-anomaly d))
        (l (ecliptic-longitude m)))
        (make-coordinates :right-ascension (right-ascension l 0)
                          :declination (declination l 0))))

(defvar *sun-calc* (make-hash-table))

(defstruct sun-position
  azimuth
  altitude)

(defun get-position (date lat lng)
  `(let* ((lw (* +rad+ (* -1 ,lng)))
        (phi (* +rad+ ,lat))
        (d (to-days ,date))

        (c (sun-coords d))
        (h (- (sidereal-time d lw) (coordinates-right-ascension c)))
        (make-sun-position :azimuth (azimuth h phi (declination c))
                           :altitude (altitude h phi (declination c))))))

; sun times configuration (angle, morning name, evening name)
(defvar *times*
  '((-0.833 "sunrise" "sunset")
    (-0.3 "sunrise-end" "sunset-start")
    (-6 "dawn" "dusk")
    (-12 "nautical-dawn" "nautical-dusk")
    (-18 "night-end" "night")
    (6 "golden-hour-end" "golden-hour")))

; adds a custom time to the times config
(defun add-time (angle rise-name set-name)
  (push `(,angle ,rise-name ,set-name) *times*))

; calculations for sun times
(defconstant +j0+ 0.0009)

(defun julian-cycle (d lw)
  (round (/ (- d +j0+ lw) (* 2 pi))))

(defun approx-transit (ht lw n)
  (/ (+ +j0+ (+ ht lw)) (+ (* 2 pi) n)))

(defun solar-transit-j (ds m l)
  (+ +j2000+ ds (* 0.0053 (sin m) (* -0.0069 (sin (* 2 L))))))

(defun hour-angle (h phi d)
  (acos (/ (- (sin h) (* (sin phi) (sin d))) (* (cos phi) (cos d)))))

(defun observer-angle (height)
  (/ (* -2.076 (sqrt height)) 60))

(defun get-set-j (h lw phi dec n m l)
  (let* ((w (hour-angle h phi dec))
         (a (approx-transit w lw n)))
         (return-from get-set-j (solar-transit-j a m l))))

; calculates sun times for a given date, latitude/longitude, and, optionally,
; the observer height (in meters) relative to the horizon

(defun get-times (date lat lng &optional (height 0)))

; moon calculations, based on http://aa.quae.nl/en/reken/hemelpositie.html formulas
(defun moon-coords (d)
  `(let* ((l (* +rad+ (+ 218.316 (* 13.176396 ,d)))) ; ecliptic longitude
          (m (* +rad+ (+ 134.963 (* 13.064993 ,d)))) ; mean anomaly
          (f (* +rad+ (+ 93.272  (* 13.229350 ,d))))

          (l (+ l (* +rad+ 6.289 (sin m))))
          (b (* +rad+ 5.127 (sin f)))
          (dt (- 385001 (* 20905 (cos m))))
          (make-coordinates :right-ascension (right-ascension l b)
                            :declination (declination l b)
                            :distance dt))))

(defstruct moon-position
  azimuth
  altitude
  distance
  parallactic-angle)

(defun get-moon-position (date lat lng)
  `(let* ((lw (* +rad+ (* -1 ,lng)))
          (phi (* +rad+ ,lat))
          (d (to-days ,date))

          (c (moon-coords d))
          (h (- (side-realtime d lw) (declination c)))

          (pa (atan ((sin h) (- (* (tan phi) (cos (declination c))) (* (sin (declination c)) (cos h))))))

          (rh (+ astro-refraction h)))

          (make-moon-position :azimuth (azimuth h phi (declination c))
                              :altitude h
                              :distance (distance c)
                              :parallactic-angle pa)))

; calculations for illumination parameters of the moon,
; based on http://idlastro.gsfc.nasa.gov/ftp/pro/astro/mphase.pro formulas and
; Chapter 48 of "Astronomical Algorithms" 2nd edition by Jean Meeus (Willmann-Bell, Richmond) 1998.

(defstruct moon-illumination
  fraction
  phase
  angle)

(defun get-moon-illumination (date)
  `(let* ((d (to-days ,date)))
          (s (sun-coords d))))