;;; a3madkour-publish-async-test.el --- tests for -async.el  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'a3madkour-publish-async)

(ert-deftest a3-pub-async-test/synchronous-p-defaults-nil ()
  "Async mode is the default; tests opt into sync mode."
  (should-not a3-pub-async--synchronous-p))

(ert-deftest a3-pub-async-test/synchronous-p-can-be-let-bound ()
  (let ((a3-pub-async--synchronous-p t))
    (should a3-pub-async--synchronous-p)))

(ert-deftest a3-pub-async-test/run-process-sync-calls-on-done-with-rc ()
  "In sync mode, run-process invokes call-process and fires on-done
inline with (rc stderr-tail)."
  (let ((calls nil) (result nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (cmd _ _ _ &rest args)
                 (push (cons cmd args) calls) 0)))
      (let ((a3-pub-async--synchronous-p t))
        (a3-pub-async/run-process "true" '("a" "b")
                                  :on-done (lambda (rc tail)
                                             (setq result (cons rc tail))))))
    (should (equal (car calls) '("true" "a" "b")))
    (should (= 0 (car result)))
    (should (or (null (cdr result)) (string-empty-p (cdr result))))))

(ert-deftest a3-pub-async-test/run-process-sync-nonzero-rc-passes-through ()
  "Non-zero exit code is reported as-is to on-done."
  (let ((rc-seen nil))
    (cl-letf (((symbol-function 'call-process) (lambda (&rest _) 2)))
      (let ((a3-pub-async--synchronous-p t))
        (a3-pub-async/run-process "false" nil
                                  :on-done (lambda (rc _tail) (setq rc-seen rc)))))
    (should (= 2 rc-seen))))

(ert-deftest a3-pub-async-test/run-process-async-spawns-make-process ()
  "In async mode, run-process uses make-process and the sentinel
fires on-done with the exit code."
  (let ((done-rc nil) (done-tail nil))
    ;; Use a tiny real subprocess: /bin/sh -c 'exit 0'.
    (a3-pub-async/run-process "/bin/sh" '("-c" "exit 0")
                              :name "test-sh"
                              :on-done (lambda (rc tail)
                                         (setq done-rc rc done-tail tail)))
    ;; Wait up to 5s for the sentinel.
    (with-timeout (5 (error "sentinel never fired"))
      (while (null done-rc) (accept-process-output nil 0.05)))
    (should (= 0 done-rc))))

(ert-deftest a3-pub-async-test/run-process-async-stderr-tail-captured ()
  "Stderr output is captured into the stderr buffer and surfaced to on-done."
  (let ((done-tail nil))
    (a3-pub-async/run-process "/bin/sh"
                              '("-c" "echo OOPS 1>&2 ; exit 1")
                              :name "test-err"
                              :on-done (lambda (_rc tail) (setq done-tail tail)))
    (with-timeout (5 (error "sentinel never fired"))
      (while (null done-tail) (accept-process-output nil 0.05)))
    (should (string-match-p "OOPS" done-tail))))

(ert-deftest a3-pub-async-test/run-process-auto-stderr-buf-killed-after-done ()
  "When run-process auto-creates its stderr buffer, the buffer is
killed after on-done fires (no leak)."
  (let ((done-fired nil) (buf-name "*a3-pub-stderr test-kill*"))
    ;; Pre-clear any stale buffer.
    (when (get-buffer buf-name) (kill-buffer buf-name))
    (a3-pub-async/run-process "/bin/sh" '("-c" "exit 0")
                              :name "test-kill"
                              :on-done (lambda (_rc _tail) (setq done-fired t)))
    (with-timeout (5 (error "sentinel never fired"))
      (while (not done-fired) (accept-process-output nil 0.05)))
    (should-not (get-buffer buf-name))))

(ert-deftest a3-pub-async-test/run-process-caller-owned-stderr-buf-preserved ()
  "When the caller passes :stderr-buf, run-process leaves it alone."
  (let* ((buf (generate-new-buffer "*owned-stderr*"))
         (done-fired nil))
    (a3-pub-async/run-process "/bin/sh" '("-c" "echo HI 1>&2 ; exit 0")
                              :name "test-owned"
                              :stderr-buf buf
                              :on-done (lambda (_rc _tail) (setq done-fired t)))
    (with-timeout (5 (error "sentinel never fired"))
      (while (not done-fired) (accept-process-output nil 0.05)))
    (should (buffer-live-p buf))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/barrier-fires-on-nth-call ()
  "N=3: on-all-done fires exactly once, after the 3rd report,
with results in registration order."
  (let ((fired 0) (saw nil))
    (let ((report (a3-pub-async/barrier 3
                                        :on-all-done
                                        (lambda (results)
                                          (cl-incf fired)
                                          (setq saw results)))))
      (funcall report 'a)
      (funcall report 'b)
      (should (= 0 fired))
      (funcall report 'c))
    (should (= 1 fired))
    (should (equal saw '(a b c)))))

(ert-deftest a3-pub-async-test/barrier-n-zero-fires-immediately ()
  "N=0: on-all-done fires immediately with nil."
  (let ((fired nil))
    (a3-pub-async/barrier 0 :on-all-done (lambda (results)
                                           (setq fired (or results 'empty))))
    (should (eq fired 'empty))))

(ert-deftest a3-pub-async-test/barrier-extra-calls-after-n-are-ignored ()
  "Calls beyond N are silently ignored (defensive against double-fire)."
  (let ((fired 0))
    (let ((report (a3-pub-async/barrier 2
                                        :on-all-done
                                        (lambda (_) (cl-incf fired)))))
      (funcall report 'a)
      (funcall report 'b)
      (funcall report 'c)
      (funcall report 'd))
    (should (= 1 fired))))

(ert-deftest a3-pub-async-test/run-struct-fields ()
  (let ((r (make-a3-pub-async-run
            :id 'test :scope 'deliberate
            :source-label "essays/x" :start-time '(0 0 0 0)
            :planned-steps 5 :completed-steps 0 :status :running)))
    (should (eq (a3-pub-async-run-scope r) 'deliberate))
    (should (= 5 (a3-pub-async-run-planned-steps r)))))

(ert-deftest a3-pub-async-test/lock-defaults-nil ()
  (should-not a3-pub-async--in-flight-run))

(ert-deftest a3-pub-async-test/buffer-getter-creates-once ()
  (let ((buf (a3-pub-async/buffer)))
    (should (bufferp buf))
    (should (eq buf (a3-pub-async/buffer)))
    (with-current-buffer buf
      (should (eq major-mode 'a3-pub-mode)))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/log-step-running-formats-line ()
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run :buffer buf
                                     :section-start (point-min))))
    (a3-pub-async/log-step run "xelatex" :running :detail "pass 2/4")
    (with-current-buffer buf
      (should (string-match-p "\\[·\\] xelatex" (buffer-string)))
      (should (string-match-p "pass 2/4" (buffer-string)))
      (should (string-match-p "running" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/log-step-ok-shows-checkmark-and-elapsed ()
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run :buffer buf
                                     :section-start (point-min))))
    (a3-pub-async/log-step run "pdf" :ok :detail "place" :elapsed 1.234)
    (with-current-buffer buf
      (should (string-match-p "\\[✓\\] pdf" (buffer-string)))
      (should (string-match-p "1\\.2s" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/log-step-err-includes-snippet ()
  (let* ((buf (a3-pub-async/buffer))
         (run (make-a3-pub-async-run :buffer buf
                                     :section-start (point-min))))
    (a3-pub-async/log-step run "xelatex" :err :elapsed 8.3
                           :err-snippet "Missing font: foo")
    (with-current-buffer buf
      (should (string-match-p "\\[✗\\] xelatex" (buffer-string)))
      (should (string-match-p "Missing font: foo" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest a3-pub-async-test/modeline-format-running ()
  (let ((run (make-a3-pub-async-run :status :running
                                    :planned-steps 9 :completed-steps 5)))
    (should (string-match-p "5/9"
                            (a3-pub-async--modeline-string run)))))

(ert-deftest a3-pub-async-test/modeline-empty-when-idle ()
  (let ((a3-pub-async--in-flight-run nil))
    (should (string-empty-p (a3-pub-async--modeline-string nil)))))

(ert-deftest a3-pub-async-test/modeline-format-cancelled ()
  (let ((run (make-a3-pub-async-run :status :cancelled
                                    :planned-steps 9 :completed-steps 3)))
    (should (string-match-p "cancelled"
                            (a3-pub-async--modeline-string run)))))

(ert-deftest a3-pub-async-test/begin-acquires-lock ()
  (let ((a3-pub-async--in-flight-run nil))
    (cl-letf (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil)))
      (let ((run (a3-pub-async/begin-publish :scope 'deliberate
                                             :source-label "essays/x"
                                             :planned-steps 5)))
        (should (eq a3-pub-async--in-flight-run run))
        (should (eq (a3-pub-async-run-status run) :running))
        (should (= 5 (a3-pub-async-run-planned-steps run)))))))

(ert-deftest a3-pub-async-test/begin-second-call-errors ()
  (let ((a3-pub-async--in-flight-run
         (make-a3-pub-async-run :id 'existing :status :running)))
    (cl-letf (((symbol-function 'a3madkour-pub/begin-publish) (lambda (&rest _) nil))
              ((symbol-function 'pop-to-buffer) (lambda (_) nil)))
      (should-error (a3-pub-async/begin-publish :scope 'deliberate
                                                :source-label "essays/y"
                                                :planned-steps 5)
                    :type 'user-error))))

(ert-deftest a3-pub-async-test/finish-releases-lock-on-ok ()
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time))))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil)))
        (a3-pub-async/finish-publish run :scope 'deliberate :status 'ok)
        (should-not a3-pub-async--in-flight-run)
        (should (eq (a3-pub-async-run-status run) :ok))))))

(ert-deftest a3-pub-async-test/finish-releases-lock-on-err ()
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time))))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil)))
        (a3-pub-async/finish-publish run :scope 'deliberate :status 'err)
        (should-not a3-pub-async--in-flight-run)))))

(ert-deftest a3-pub-async-test/finish-cancelled-skips-citation-emit ()
  "On cancelled, the citations emit-yaml tail does NOT fire."
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time)))
         (emit-fired nil))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil))
                ((symbol-function 'a3madkour-pub-citations/emit-yaml)
                 (lambda (&rest _) (setq emit-fired t))))
        (a3-pub-async/finish-publish run :scope 'deliberate :status 'cancelled)
        (should-not emit-fired)))))

(ert-deftest a3-pub-async-test/cancel-noop-when-idle ()
  (let ((a3-pub-async--in-flight-run nil))
    (should-not (a3-pub-async/cancel-current-run))))

(ert-deftest a3-pub-async-test/cancel-interrupts-live-processes ()
  (let* ((run (make-a3-pub-async-run :status :running)))
    (cl-letf* ((interrupted nil)
               ((symbol-function 'interrupt-process)
                (lambda (p) (push p interrupted)))
               ((symbol-function 'process-live-p) (lambda (_) t))
               ((symbol-function 'processp) (lambda (_) t)))
      (setf (a3-pub-async-run-live-processes run) '(p1 p2))
      (let ((a3-pub-async--in-flight-run run))
        (a3-pub-async/cancel-current-run))
      (should (memq 'p1 interrupted))
      (should (memq 'p2 interrupted))
      (should (eq (a3-pub-async-run-status run) :cancelled)))))

(ert-deftest a3-pub-async-test/cancel-deletes-tmp-dirs ()
  (let* ((tmp1 (make-temp-file "a3-pub-cancel-" t))
         (tmp2 (make-temp-file "a3-pub-cancel-" t))
         (run (make-a3-pub-async-run :status :running
                                     :tmp-dirs (list tmp1 tmp2))))
    (let ((a3-pub-async--in-flight-run run))
      (a3-pub-async/cancel-current-run))
    (should-not (file-directory-p tmp1))
    (should-not (file-directory-p tmp2))))

(ert-deftest a3-pub-async-test/with-sync-helper-binds-var ()
  (with-a3-pub-async-sync
   (should a3-pub-async--synchronous-p))
  (should-not a3-pub-async--synchronous-p))

(ert-deftest a3-pub-async-test/mode-binds-cancel ()
  "C-c C-c in *a3-publish* is bound to cancel-current-run."
  (with-current-buffer (a3-pub-async/buffer)
    (should (eq (lookup-key a3-pub-mode-map (kbd "C-c C-c"))
                'a3-pub-async/cancel-current-run))))

(ert-deftest a3-pub-async-test/finish-ok-fires-citation-emit-on-living ()
  "Citations emit-yaml fires on (status='ok, scope='living) too — matches
the pre-async F slice behavior where BOTH a3-publish-deliberate and
a3-publish-living tail-called emit-yaml."
  ;; Preload citations so the (require ...) inside finish-publish is a
  ;; no-op — otherwise loading the real file would overwrite the cl-letf
  ;; stub on emit-yaml.
  (require 'a3madkour-publish-citations)
  (let* ((run (make-a3-pub-async-run :id 'r :status :running
                                     :buffer (a3-pub-async/buffer)
                                     :start-time (current-time)))
         (emit-fired nil))
    (let ((a3-pub-async--in-flight-run run))
      (cl-letf (((symbol-function 'a3madkour-pub/finish-publish) (lambda (&rest _) nil))
                ((symbol-function 'a3madkour-pub-citations/emit-yaml)
                 (lambda (&rest _) (setq emit-fired t))))
        (a3-pub-async/finish-publish run :scope 'living :status 'ok)
        (should emit-fired)))))

(ert-deftest a3-pub-async-test/run-process-stdout-buf-captures-output ()
  "When :stdout-buf is passed, on-done's 2nd arg is the stdout content."
  (let ((seen-tail nil))
    (cl-letf (((symbol-function 'call-process)
               (lambda (_cmd _ buf _ &rest _args)
                 (when (bufferp buf) (with-current-buffer buf (insert "HELLO\n"))) 0)))
      (with-a3-pub-async-sync
       (let ((stdout-buf (generate-new-buffer "*stdout-test*")))
         (unwind-protect
             (a3-pub-async/run-process
              "/bin/true" nil
              :name "stdout-test"
              :stdout-buf stdout-buf
              :on-done (lambda (_rc tail) (setq seen-tail tail)))
           (kill-buffer stdout-buf)))))
    (should (string-match-p "HELLO" seen-tail))))

(provide 'a3madkour-publish-async-test)
;;; a3madkour-publish-async-test.el ends here
