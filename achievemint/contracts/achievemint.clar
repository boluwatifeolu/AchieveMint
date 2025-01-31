
;; AchieveMint
;; A digital achievement system with cross-community engagement rewards

(define-non-fungible-token achievement-token uint)
(define-non-fungible-token merit-token uint)

(define-map achievements 
    { achievement-id: uint } 
    { 
        title: (string-ascii 50),
        timestamp: uint,
        max-earners: uint,
        current-earners: uint,
        merit-value: uint,
        community-tags: (list 10 (string-ascii 20))
    }
)

(define-map earner-achievements 
    { earner: principal } 
    { tokens: (list 100 uint) }
)

(define-map earner-merits
    { earner: principal }
    { 
        total-merits: uint,
        spent-merits: uint,
        community-multipliers: (list 10 uint)
    }
)

(define-map achievement-earners
    { achievement-id: uint }
    { earners: (list 1000 principal) }
)

(define-map community-partnerships
    { community-tag: (string-ascii 20) }
    { partnership-multiplier: uint }
)

(define-data-var token-counter uint u0)
(define-data-var achievement-counter uint u0)

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ACHIEVEMENT-FULL (err u101))
(define-constant ERR-ALREADY-EARNED (err u102))
(define-constant ERR-INSUFFICIENT-MERITS (err u103))
(define-constant ERR-MERIT-AWARD-FAILED (err u104))
(define-constant ERR-INVALID-ACHIEVEMENT-PARAMS (err u105))
(define-constant ERR-COMMUNITY-NOT-FOUND (err u106))
(define-constant ERR-INVALID-COMMUNITY-TAG (err u107))

;; Validation Constants
(define-constant MAX-TITLE-LENGTH u50)
(define-constant MAX-EARNERS u1000)
(define-constant MAX-MERIT-VALUE u10000)
(define-constant MAX-COMMUNITY-TAGS u10)
(define-constant MAX-PARTNERSHIP-MULTIPLIER u5)
(define-constant MAX-COMMUNITY-TAG-LENGTH u20)

;; Administrative Functions

(define-public (create-community-partnership 
    (community-tag (string-ascii 20)) 
    (multiplier uint)
)
    (begin
        (asserts! 
            (and 
                (> (len community-tag) u0)
                (<= (len community-tag) MAX-COMMUNITY-TAG-LENGTH)
            ) 
            ERR-INVALID-COMMUNITY-TAG
        )

        (asserts! 
            (and 
                (> multiplier u0)
                (<= multiplier MAX-PARTNERSHIP-MULTIPLIER)
            ) 
            ERR-INVALID-ACHIEVEMENT-PARAMS
        )

        (try! (is-contract-owner))
        (map-set community-partnerships 
            { community-tag: community-tag }
            { partnership-multiplier: multiplier }
        )
        (ok community-tag)
    )
)

(define-public (create-achievement 
    (title (string-ascii 50)) 
    (timestamp uint) 
    (max-earners uint) 
    (merit-value uint)
    (community-tags (list 10 (string-ascii 20)))
)
    (begin
        (asserts! 
            (and 
                (> (len title) u0)
                (<= (len title) MAX-TITLE-LENGTH)
            ) 
            ERR-INVALID-ACHIEVEMENT-PARAMS
        )

        (asserts! 
            (<= (len community-tags) MAX-COMMUNITY-TAGS) 
            ERR-INVALID-ACHIEVEMENT-PARAMS
        )

        (asserts! (> timestamp block-height) ERR-INVALID-ACHIEVEMENT-PARAMS)

        (asserts! 
            (and 
                (> max-earners u0)
                (<= max-earners MAX-EARNERS)
            ) 
            ERR-INVALID-ACHIEVEMENT-PARAMS
        )

        (asserts! 
            (and 
                (> merit-value u0)
                (<= merit-value MAX-MERIT-VALUE)
            ) 
            ERR-INVALID-ACHIEVEMENT-PARAMS
        )

        (let
            ((achievement-id (+ (var-get achievement-counter) u1)))
            (try! (is-contract-owner))
            (map-set achievements 
                { achievement-id: achievement-id }
                {
                    title: title,
                    timestamp: timestamp,
                    max-earners: max-earners,
                    current-earners: u0,
                    merit-value: merit-value,
                    community-tags: community-tags
                }
            )
            (var-set achievement-counter achievement-id)
            (ok achievement-id)
        )
    )
)

(define-public (earn-achievement (achievement-id uint))
    (let
        ((achievement (unwrap! (map-get? achievements { achievement-id: achievement-id }) (err u404)))
         (current-count (get current-earners achievement))
         (max-count (get max-earners achievement)))
        
        (asserts! (< current-count max-count) ERR-ACHIEVEMENT-FULL)
        (asserts! (has-not-earned tx-sender achievement-id) ERR-ALREADY-EARNED)
        
        (let
            ((token-id (+ (var-get token-counter) u1))
             (merits-result (calculate-community-merits 
                 tx-sender 
                 (get merit-value achievement) 
                 (get community-tags achievement)
             )))
            
            (unwrap! merits-result ERR-MERIT-AWARD-FAILED)
            (var-set token-counter token-id)
            (try! (nft-mint? achievement-token token-id tx-sender))
            
            (map-set earner-achievements
                { earner: tx-sender }
                { tokens: (append-token (default-to (list ) (get tokens (map-get? earner-achievements { earner: tx-sender }))) token-id) }
            )
            
            (map-set achievements 
                { achievement-id: achievement-id }
                (merge achievement { current-earners: (+ current-count u1) })
            )
            
            (ok token-id)
        )
    )
)

(define-public (spend-merits (merits uint))
    (let
        ((earner-info (unwrap! (map-get? earner-merits { earner: tx-sender }) (err u404)))
         (available-merits (- (get total-merits earner-info) (get spent-merits earner-info))))
        
        (asserts! (>= available-merits merits) ERR-INSUFFICIENT-MERITS)
        
        (map-set earner-merits
            { earner: tx-sender }
            { 
                total-merits: (get total-merits earner-info),
                spent-merits: (+ (get spent-merits earner-info) merits),
                community-multipliers: (get community-multipliers earner-info)
            }
        )
        
        (ok merits)
    )
)

;; Helper Functions

(define-private (is-contract-owner)
    (ok (asserts! (is-eq tx-sender contract-caller) ERR-UNAUTHORIZED))
)

(define-private (has-not-earned (earner principal) (achievement-id uint))
    (is-none (index-of 
        (default-to (list ) 
            (get earners (map-get? achievement-earners { achievement-id: achievement-id }))
        )
        earner
    ))
)

(define-private (append-token (tokens (list 100 uint)) (token-id uint))
    (unwrap! (as-max-len? (append tokens token-id) u100) tokens)
)

(define-private (calculate-community-merits 
    (earner principal) 
    (base-merits uint)
    (achievement-communities (list 10 (string-ascii 20)))
)
    (let
        ((current-merits (default-to 
            { 
                total-merits: u0, 
                spent-merits: u0, 
                community-multipliers: (list ) 
            } 
            (map-get? earner-merits { earner: earner })))
         (community-bonus (calculate-community-bonus achievement-communities)))
        
        (map-set earner-merits
            { earner: earner }
            {
                total-merits: (+ 
                    (get total-merits current-merits) 
                    (* base-merits (+ u1 community-bonus))
                ),
                spent-merits: (get spent-merits current-merits),
                community-multipliers: (append-multiplier 
                    (get community-multipliers current-merits) 
                    community-bonus
                )
            }
        )
        (ok base-merits)
    )
)

(define-private (calculate-community-bonus (communities (list 10 (string-ascii 20))))
    (fold 
        + 
        (map get-community-multiplier communities)
        u0
    )
)

(define-private (get-community-multiplier (community-tag (string-ascii 20)))
    (default-to u0 
        (get partnership-multiplier 
            (map-get? community-partnerships { community-tag: community-tag })
        )
    )
)

(define-private (append-multiplier 
    (multipliers (list 10 uint)) 
    (multiplier uint)
)
    (unwrap! 
        (as-max-len? 
            (if (is-none (index-of multipliers multiplier))
                (append multipliers multiplier)
                multipliers
            ) 
            u10
        ) 
        multipliers
    )
)

;; Read-Only Functions

(define-read-only (get-earner-achievements (earner principal))
    (map-get? earner-achievements { earner: earner })
)

(define-read-only (get-earner-merits (earner principal))
    (map-get? earner-merits { earner: earner })
)

(define-read-only (get-achievement-details (achievement-id uint))
    (map-get? achievements { achievement-id: achievement-id })
)

(define-read-only (get-community-partnership (community-tag (string-ascii 20)))
    (map-get? community-partnerships { community-tag: community-tag })
)