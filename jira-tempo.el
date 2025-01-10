;;; jira-tempo.el --- Jira Tempo Extension  -*- lexical-binding: t -*-

;; Copyright (C) 2025 Pablo González Carrizo

;; Author: Pablo González Carrizo <unmonoqueteclea@gmail.com>
;; Created: 2025-02-16

;; This file is NOT part of GNU Emacs.

;;; Commentary:

;; Manage worklogs from Jira Tempo Extension

;;; Code:

(require 'json)
(require 'transient)

(require 'jira-api)
(require 'jira-fmt)
(require 'jira-table)

(defvar jira-tempo-fields
  '((:key . ((:path . (tempoWorklogId))
               (:columns . 10)
               (:name . "Key")
               (:formatter . jira-fmt-issue-key)))
    (:time . ((:path . (timeSpentSeconds))
               (:columns . 10)
               (:name . "Time")
               (:formatter . jira-fmt-time-from-secs)))
    (:date . ((:path . (startDate))
               (:columns . 18)
               (:name . "Date")
               (:formatter . (lambda (v) (jira-fmt-date v t)))))
    (:description . ((:path . (description))
               (:columns . 70)
               (:name . "Issue description"))))
  "Fields that can be shown in the tabulated list")

(defvar jira-tempo-table-fields
  '(:key :time :date :description)
  "Tempo fields to show in the tabulated list")

(defcustom jira-tempo-max-results 50
  "Maximum number of Tempo worklogs to retrieve"
  :group 'jira :type 'integer)

(defun jira-tempo--api-get-worklogs (callback)
  (let ((start-end (jira-utils-week-start-and-end (current-time))))
    (jira-api-tempo-call
     "GET" (concat "worklogs/user/" jira-account-id)
     :params `(("from" . ,(car start-end)) ("to" . ,(car (cdr start-end))))
     :callback callback)))

(defun jira-tempo--api-delete-worklog (worklog-id)
  (jira-api-tempo-call "DELETE" (concat "worklogs/" worklog-id)
     :callback (lambda (data response) (tablist-revert))))

(defun jira-tempo--data-accumulate-time-per-day (worklogs)
  (let ((time-per-day (make-hash-table :test 'equal)))
    (dolist (worklog (append worklogs nil))
      (let* ((date (jira-table-extract-field jira-tempo-fields :date worklog))
             (time (jira-table-extract-field jira-tempo-fields :time worklog))
             (current-time (gethash date time-per-day 0)))
        (puthash date (+ current-time time) time-per-day)))
    time-per-day))

(defun jira-tempo--data-format-cell (worklog field)
  (let* ((extracted (jira-table-extract-field jira-tempo-fields field worklog))
         (formatter (jira-table-field-formatter jira-tempo-fields field))
         (value (format "%s" (or extracted ""))))
    (if formatter (funcall formatter value) value)))

(defun jira-tempo--data-format-worklogs (worklogs)
  (let ((time-per-day (jira-tempo--data-accumulate-time-per-day worklogs)))
    (mapcar
     (lambda (worklog)
       (let* ((key (jira-table-extract-field jira-tempo-fields :key worklog))
              (formatter (lambda (field) (jira-tempo--data-format-cell worklog field)))
              (date (jira-table-extract-field jira-tempo-fields :date worklog))
              (accumulated-time
               (jira-fmt-time-from-secs
                (number-to-string (gethash date time-per-day 0)))))
         (list key (vconcat
                    (vector accumulated-time)
                    (mapcar formatter jira-tempo-table-fields)))))
     worklogs)))

(defun jira-tempo--refresh-table (data response)
  (let* ((data-alist (json-read-from-string (json-encode data)))
         (worklogs (alist-get 'results data-alist))
         (entries (jira-tempo--data-format-worklogs worklogs)))
    (setq tabulated-list-entries entries)
    (tabulated-list-print t t)))

(defun jira-tempo--refresh ()
  (jira-tempo--api-get-worklogs #'jira-tempo--refresh-table))

(transient-define-prefix jira-tempo-menu ()
  "Show menu for actions on Jira Tempo worklogs"
  [["Jira Tempo Worklogs List"
    ("?" "Show this menu" jira-tempo-menu)
    ("g" "Refresh list" tablist-revert)]]
  [[:description
    (lambda () (jira-utils-transient-description "Actions on selected worklog"))
    :inapt-if-not jira-utils-marked-item
    ("D" "Delete worklog"
     (lambda () (interactive)
       (jira-tempo--api-delete-worklog
        (format "%s"(jira-utils-marked-item)))))]]

  (interactive)
  (transient-setup 'jira-tempo-menu))

(defvar jira-tempo-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "?" 'jira-tempo-menu)
    (define-key map "D"
                (lambda () (interactive)
                  (jira-tempo--api-delete-worklog
                   (format "%s"(jira-utils-marked-item)))))
    map)
  "Keymap for `jira-tempo-mode'.")

;;;###autoload (autoload 'jira-tempo "jira-tempo" nil t)
(defun jira-tempo ()
  "List Jira Tempo Worklogs"
  (interactive)
  (pop-to-buffer "*Jira Tempo*")
  (delete-other-windows)
  (jira-api-get-account-id :callback #'jira-tempo-mode))

(define-derived-mode jira-tempo-mode tabulated-list-mode "Jira Tempo"
  "Major mode for handling a list of Jira Tempo Worklogs"
  :interactive  nil
  (setq tabulated-list-entries '())
  (let ((name (lambda (fd) (jira-table-field-name jira-tempo-fields fd)))
        (columns (lambda (fd) (jira-table-field-columns jira-tempo-fields fd))))
    (setq tabulated-list-format
          (vconcat '[("Time (Day)" 15 t)]
                   (mapcar
                    (lambda (field)
                      (list (funcall name field) (funcall columns field) t))
                    jira-tempo-table-fields))))
  (setq tabulated-list-padding 2)
  (add-hook 'tabulated-list-revert-hook 'jira-tempo--refresh nil t)
  (tabulated-list-init-header)
  (tablist-minor-mode)
  (tabulated-list-revert)
  (tablist-revert))

(provide 'jira-tempo)

;; jira-tempo.el ends here
