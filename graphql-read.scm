(define (deb x)
  (write x)
  (newline)
  x)

(define ascii-digit "0123456789")
(define name-leader "_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
(define name-subseq (string-append name-leader ascii-digit))

(define last-token (make-parameter #f))

(define (graphql-string->symbol string)
  (string->symbol (string-map (lambda (ch) (if (char=? ch #\_) #\- ch))
                              string)))

(define (punctuator-char? c)
  (case c
    ((#\! #\$ #\( #\) #\: #\= #\@ #\[ #\] #\{ #\| #\}) #t)
    (else #f)))

(define (read-punctuator?)
  (cond ((read-char? punctuator-char?))
        ((read-char? #\.)
         (unless (and (read-char? #\.) (read-char? #\.))
           (error "Saw dot, expected ellipsis")))
        (else #f)))

(define (skip-comment)
  (unless (or (read-char? eof-object?)
              (read-char? #\newline)
              (read-char? #\return))
    (skip-comment)))

(define (skip-whitespace-and-comments)
  (cond ((read-char? #\#)
         (skip-comment)
         (skip-whitespace-and-comments))
        ((or (read-char? #\space) (read-char? #\tab))
         (skip-whitespace-and-comments))))

(define (read-name?)
  (let ((leader (read-char? name-leader)))
    (and leader
         (graphql-string->symbol
          (string-append (string leader) (read-char* name-subseq))))))

(define (read-string-char)
  (cond ((or (read-char? eof-object?)
             (read-char? #\newline)
             (read-char? #\return))
         (error "Newline inside quoted string"))
        ((read-char? #\\)
         (or (and (read-char #\u)
                  (let ((char (read-char "bfnrt\"\\/")))
                    (case char
                      ((#\b) #\x08)
                      ((#\f) #\x0c)
                      ((#\n) #\newline)
                      ((#\r) #\return)
                      ((#\t) #\tab)
                      (else char))))))
        (else (read-char? (lambda (_) #t)))))

(define (read-double-quoted-string)
  (let loop ((chars '()))
    (if (read-char? #\")
        (list->string chars)
        (loop (append chars (list (read-string-char)))))))

(define (read-triple-quoted-string)
  (let loop ((chars '()))
    (if (read-char? #\")
        (if (read-char? #\")
            (if (read-char? #\")
                (list->string chars)
                (loop (append chars '(#\" #\"))))
            (loop (append chars '(#\"))))
        (loop (append chars (list (read-string-char)))))))

(define (read-string?)
  (and (read-char? #\")
       (if (read-char? #\")
           (if (read-char? #\")
               (read-triple-quoted-string)
               "")
           (read-double-quoted-string))))

(define (read-number?)
  (let ((negative? (not (not (read-char? #\-)))))
    (if (read-char? #\0)
        (if (read-char? ascii-digit)
            (error "GraphQL syntax does not permit leading zeros")
            0)
        (let ((digits (read-char* ascii-digit)))
          (cond (digits (* (if negative? -1 1) (string->number digits)))
                (negative? (error "Minus sign not followed by number"))
                (else #f))))))

(define (read-token-really)
  (skip-whitespace-and-comments)
  (if (eof-object? (peek-char))
      (eof-object)
      (or (read-punctuator?)
          (read-string?)
          (read-number?)
          (read-name?)
          (error "Syntax error"))))

(define (read-token? match?)
  (let ((token (or (last-token) (read-token-really))))
    (cond ((match? token) (last-token #f) token)
          (else (last-token token) #f))))

(define (equal char)
  (lambda (x) (equal? char x)))

(define (one-of-the-symbols? symbols)
  (lambda (x) (and (symbol? x) (member x symbols))))

(define (read-selection-set)
  (and (read-token? (equal #\{))
       (let loop ((selections '()))
         (if (read-token? (equal #\}))
             selections
             (let ((selection (or (read-token? symbol?)
                                  (error "Selection expected"))))
               (loop (append selections (list selection))))))))

(define (read-operation?)
  (let ((operation-type
         (read-token? (one-of-the-symbols? '(query mutation subscription)))))
    (and operation-type
         (let* ((operation-name (or (read-token? symbol?)
                                    (error "No operation name")))
                (selection-set (read-selection-set)))
           (append (list operation-type operation-name)
                   selection-set)))))

(define (graphql-read-document)
  (let loop ((document '()))
    (if (read-token? eof-object?)
        document
        (loop
         (append document
                 (list (or (read-operation?)
                           (error "Cannot parse GraphQL document"))))))))

(define (string->graphql document-as-string)
  (parameterize ((current-input-port (open-input-string document-as-string))
                 (last-token #f))
    (graphql-read-document)))
