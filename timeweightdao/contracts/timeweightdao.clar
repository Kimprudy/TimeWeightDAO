;; TimeWeightDAO: Dynamic Time-Weighted Governance System
;; A governance system where voting power scales with token holding duration

;; Traits
(define-trait governance-token-trait 
    ((transfer (uint principal principal (optional (buff 34))) (response bool uint))
     (get-balance (principal) (response uint uint))))

;; Constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROPOSAL (err u101))
(define-constant ERR_PROPOSAL_ACTIVE (err u102))
(define-constant ERR_PROPOSAL_ENDED (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_TOKEN_NOT_SET (err u106))

(define-constant VOTING_PERIOD u144) ;; ~24 hours in blocks
(define-constant MIN_PROPOSAL_THRESHOLD u100000000) ;; Minimum tokens needed to create proposal
(define-constant POWER_MULTIPLIER u100) ;; Base multiplier for voting power calculations
(define-constant MAX_HOLDING_BONUS u300) ;; Maximum 3x voting power multiplier

;; Data Variables
(define-data-var proposal-count uint u0)
(define-data-var governance-token (optional principal) none)
(define-data-var contract-owner principal tx-sender)

;; Maps
(define-map Proposals
    {id: uint}
    {
        proposer: principal,
        title: (string-ascii 50),
        description: (string-ascii 500),
        start-block: uint,
        end-block: uint,
        for-votes: uint,
        against-votes: uint,
        executed: bool
    }
)

(define-map TokenDeposits
    {user: principal}
    {
        amount: uint,
        deposit-height: uint
    }
)

(define-map Votes
    {proposal-id: uint, voter: principal}
    {power: uint, support: bool}
)

;; Administrative Functions
(define-public (set-governance-token (new-token principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_UNAUTHORIZED)
        (ok (var-set governance-token (some new-token)))
    )
)

;; Private Functions
(define-private (calculate-voting-power (user principal))
    (let (
        (deposit (default-to {amount: u0, deposit-height: block-height} (map-get? TokenDeposits {user: user})))
        (blocks-held (- block-height (get deposit-height deposit)))
        (base-power (get amount deposit))
        (raw-bonus (* POWER_MULTIPLIER (/ blocks-held u1440))) ;; 1 day = ~1440 blocks
        (time-bonus (if (> raw-bonus MAX_HOLDING_BONUS) 
            MAX_HOLDING_BONUS
            raw-bonus))
    )
    (/ (* base-power (+ POWER_MULTIPLIER time-bonus)) POWER_MULTIPLIER))
)

;; Public Functions
(define-public (deposit-tokens (token-trait <governance-token-trait>) (amount uint))
    (let (
        (token (unwrap! (var-get governance-token) ERR_TOKEN_NOT_SET))
    )
        (asserts! (is-eq (contract-of token-trait) token) ERR_UNAUTHORIZED)
        (try! (contract-call? token-trait transfer 
            amount 
            tx-sender 
            (as-contract tx-sender) 
            none))
        (map-set TokenDeposits 
            {user: tx-sender}
            {
                amount: (+ (default-to u0 (get amount (map-get? TokenDeposits {user: tx-sender}))) amount),
                deposit-height: block-height
            }
        )
        (ok true)
    )
)

(define-public (create-proposal (title (string-ascii 50)) (description (string-ascii 500)))
    (let (
        (proposer-power (calculate-voting-power tx-sender))
        (new-id (+ (var-get proposal-count) u1))
    )
        (asserts! (>= proposer-power MIN_PROPOSAL_THRESHOLD) ERR_INSUFFICIENT_BALANCE)
        (map-set Proposals 
            {id: new-id}
            {
                proposer: tx-sender,
                title: title,
                description: description,
                start-block: block-height,
                end-block: (+ block-height VOTING_PERIOD),
                for-votes: u0,
                against-votes: u0,
                executed: false
            }
        )
        (var-set proposal-count new-id)
        (ok new-id)
    )
)

