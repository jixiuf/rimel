(librimel-get-schema-list)
(librimel-select-schema "luna_pinyin_simp")
(librimel-search "wode" nil)
(librimel-finalize)
(librimel-get-user-config "default.custom" "patch/menu/page_size" "int")
(librimel-get-user-config "build/default" "menu/page_size" "int")
(librimel-set-user-config "default.custom" "patch/menu/page_size" 100 "int")
(librimel-get-schema-config "" "speller/auto_select" "bool")
(librimel-set-schema-config "" "speller/auto_select" true "bool")
(librimel-sync-user-data)

(defun try-context()
  (librimel-clear-composition)
  (librimel-process-key (string-to-char "w"))
  (librimel-process-key (string-to-char "o"))
  (librimel-simulate-key-sequence "de")
  (librimel-process-key #xff54)         ;down
  (librimel-get-candidates)
  (librimel-get-candidates 1 3)
  (librimel-get-context))

(try-context)



(provide 'librimel-demo)

;; Local Variables:
;; coding: utf-8
;; End:

;;; librimel-demo.el ends here.
