;; Benefit Fraud Prevention Contract
;; Prevents social service fraud while protecting legitimate recipients

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))

;; Data Variables
(define-data-var total-recipients uint u0)
(define-data-var total-fraud-reports uint u0)
(define-data-var system-active bool true)

;; Data Maps
(define-map recipients
  { recipient-id: (buff 20) }
  {
    name-hash: (buff 32),
    age: uint,
    address-hash: (buff 32),
    verified: bool,
    risk-score: uint,
    last-updated: uint,
    total-benefits: uint
  }
)

(define-map fraud-reports
  { report-id: uint }
  {
    recipient-id: (buff 20),
    reporter: principal,
    description: (string-ascii 500),
    severity: uint,
    status: (string-ascii 20),
    timestamp: uint,
    investigated: bool
  }
)

(define-map authorized-agencies
  { agency: principal }
  { authorized: bool, agency-type: (string-ascii 50) }
)

(define-map recipient-benefits
  { recipient-id: (buff 20), program: (string-ascii 50) }
  { amount: uint, start-date: uint, end-date: uint, active: bool }
)

(define-map risk-factors
  { factor-type: (string-ascii 50) }
  { weight: uint, threshold: uint }
)

;; Authorization Functions
(define-private (is-authorized (caller principal))
  (or
    (is-eq caller CONTRACT-OWNER)
    (default-to false (get authorized (map-get? authorized-agencies { agency: caller })))
  )
)

;; Public Functions

;; Register a new recipient
(define-public (register-recipient
  (recipient-id (buff 20))
  (name (string-ascii 100))
  (age uint)
  (address (string-ascii 200))
)
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> age u0) ERR-INVALID-INPUT)
    (asserts! (< age u150) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? recipients { recipient-id: recipient-id })) ERR-ALREADY-EXISTS)

    (map-set recipients
      { recipient-id: recipient-id }
      {
        name-hash: (sha256 (unwrap-panic (to-consensus-buff? name))),
        age: age,
        address-hash: (sha256 (unwrap-panic (to-consensus-buff? address))),
        verified: false,
        risk-score: u0,
        last-updated: block-height,
        total-benefits: u0
      }
    )

    (var-set total-recipients (+ (var-get total-recipients) u1))
    (ok true)
  )
)

;; Verify a recipient
(define-public (verify-recipient (recipient-id (buff 20)))
  (let ((recipient-data (unwrap! (map-get? recipients { recipient-id: recipient-id }) ERR-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    (map-set recipients
      { recipient-id: recipient-id }
      (merge recipient-data { verified: true, last-updated: block-height })
    )
    (ok true)
  )
)

;; Report fraud
(define-public (report-fraud
  (recipient-id (buff 20))
  (description (string-ascii 500))
  (severity uint)
)
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> severity u0) ERR-INVALID-INPUT)
    (asserts! (<= severity u10) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? recipients { recipient-id: recipient-id })) ERR-NOT-FOUND)

    (let ((report-id (+ (var-get total-fraud-reports) u1)))
      (map-set fraud-reports
        { report-id: report-id }
        {
          recipient-id: recipient-id,
          reporter: tx-sender,
          description: description,
          severity: severity,
          status: "pending",
          timestamp: block-height,
          investigated: false
        }
      )

      (var-set total-fraud-reports report-id)
      (ok report-id)
    )
  )
)

;; Update risk score
(define-public (update-risk-score (recipient-id (buff 20)) (new-score uint))
  (let ((recipient-data (unwrap! (map-get? recipients { recipient-id: recipient-id }) ERR-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score u100) ERR-INVALID-INPUT)

    (map-set recipients
      { recipient-id: recipient-id }
      (merge recipient-data { risk-score: new-score, last-updated: block-height })
    )
    (ok true)
  )
)

;; Add benefit record
(define-public (add-benefit-record
  (recipient-id (buff 20))
  (program (string-ascii 50))
  (amount uint)
  (duration uint)
)
  (begin
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (is-some (map-get? recipients { recipient-id: recipient-id })) ERR-NOT-FOUND)

    (map-set recipient-benefits
      { recipient-id: recipient-id, program: program }
      {
        amount: amount,
        start-date: block-height,
        end-date: (+ block-height duration),
        active: true
      }
    )

    ;; Update total benefits for recipient
    (let ((recipient-data (unwrap! (map-get? recipients { recipient-id: recipient-id }) ERR-NOT-FOUND)))
      (map-set recipients
        { recipient-id: recipient-id }
        (merge recipient-data {
          total-benefits: (+ (get total-benefits recipient-data) amount),
          last-updated: block-height
        })
      )
    )
    (ok true)
  )
)

;; Authorize agency
(define-public (authorize-agency (agency principal) (agency-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-agencies
      { agency: agency }
      { authorized: true, agency-type: agency-type }
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get recipient info
(define-read-only (get-recipient (recipient-id (buff 20)))
  (map-get? recipients { recipient-id: recipient-id })
)

;; Get fraud report
(define-read-only (get-fraud-report (report-id uint))
  (map-get? fraud-reports { report-id: report-id })
)

;; Get benefit record
(define-read-only (get-benefit-record (recipient-id (buff 20)) (program (string-ascii 50)))
  (map-get? recipient-benefits { recipient-id: recipient-id, program: program })
)

;; Check if recipient is verified
(define-read-only (is-recipient-verified (recipient-id (buff 20)))
  (match (map-get? recipients { recipient-id: recipient-id })
    recipient-data (get verified recipient-data)
    false
  )
)

;; Get risk score
(define-read-only (get-risk-score (recipient-id (buff 20)))
  (match (map-get? recipients { recipient-id: recipient-id })
    recipient-data (get risk-score recipient-data)
    u0
  )
)

;; Get total recipients
(define-read-only (get-total-recipients)
  (var-get total-recipients)
)

;; Get total fraud reports
(define-read-only (get-total-fraud-reports)
  (var-get total-fraud-reports)
)

;; Check if agency is authorized
(define-read-only (is-agency-authorized (agency principal))
  (default-to false (get authorized (map-get? authorized-agencies { agency: agency })))
)
