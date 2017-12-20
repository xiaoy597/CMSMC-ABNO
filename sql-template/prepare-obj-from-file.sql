.WIDTH 256;
.LOGON $PARAM{'HOSTNM'}/$PARAM{'USERNM'},$PARAM{'PASSWD'};

SELECT * FROM $PARAM{'TEMP_DB'}.$PARAM{'LOAD_TBL'};

DELETE FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ 
WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}';

INSERT INTO $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ (ABNO_INCM_CALC_BTCH, SEC_CDE)
SELECT DISTINCT '$PARAM{'abno_incm_calc_btch'}', SEC_CDE
FROM	NSOVIEW.CSDC_INTG_SEC_INFO, $PARAM{'TEMP_DB'}.$PARAM{'LOAD_TBL'}
WHERE SEC_CDE = ITEM_NBR
AND MKT_SORT IN ($PARAM{'sec_exch_cde_quot'})
AND S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
AND E_DATE > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
;

.QUIT;

