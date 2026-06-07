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

(provide 'a3madkour-publish-async-test)
;;; a3madkour-publish-async-test.el ends here
