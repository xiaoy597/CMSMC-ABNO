.WIDTH 256;
.LOGON $PARAM{'HOSTNM'}/$PARAM{'USERNM'},$PARAM{'PASSWD'};

DELETE FROM $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL 
WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
AND SEC_EXCH_CDE = '0';

-- 沪市普通交易过户（BIZ_TYPE = 1000）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE1 AS SEC_CDE,
    '1000' AS BIZ_TYPE,
    SUM(BUY_FEE_TAX + SAL_FEE_TAX) AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SELECT
   t1.SHDR_ACCT
  ,t1.TRAD_DATE
  ,t1.SEC_CDE1
   ---买入数量
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'B' THEN t1.SETL_VOL
         ELSE 0
         END ) AS BUY_QTY     
   --卖出数量为负值
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'S' THEN -t1.SETL_VOL 
         ELSE 0
         END) AS SAL_QTY
   --买方清算金额为负
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'B' THEN -t1.CLR_AMT
         ELSE 0
         END) AS BUY_AMT
   --卖方清算金额为正
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'S' THEN t1.CLR_AMT
         ELSE 0
         END) AS SAL_AMT
   --买方税费为负
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'B' THEN -(STMP_TAX+HAND_FEE+TRAN_FEE+CMSN_CHG+ADMIN_CHRG+OTH_AMT1+OTH_AMT2+OTH_AMT3)
         ELSE 0
         END) AS BUY_FEE_TAX
   --卖方税费为负
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'S' THEN -(STMP_TAX+HAND_FEE+TRAN_FEE+CMSN_CHG+ADMIN_CHRG+OTH_AMT1+OTH_AMT2+OTH_AMT3)
         ELSE 0
         END) AS SAL_FEE_TAX
   --买方实际收付为负
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'B' THEN -t1.FACT_PAMT
         ELSE 0
         END) AS BUY_FACT_AMT
   --卖方实际收付为正
  ,SUM(CASE WHEN t1.TRAD_DIRC = 'S' THEN t1.FACT_PAMT
         ELSE 0
         END) AS SAL_FACT_AMT
FROM NSOVIEW.CSDC_H_CLR_STM_DTL t1,
      (
        SELECT PRMT_VAL AS SEC_ACCT 
        FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
        WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
      ) t2
  WHERE t1.BIZ_SORT ='001'
  AND t1.TRAD_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
  AND t1.SEC_CTG = ('PT')
  AND t1.TRANS_TYPE = '00A'
  AND t1.SHDR_ACCT NOT IN 
   (SELECT 
    DISTINCT  SEC_SETL_ACCT     --证券结算账户  去掉融券专用账户
    FROM NSOVIEW.CSDC_H_STM_ACCT_SETUP_HIS
    WHERE S_DATE <= t1.TRAD_DATE
      AND E_DATE > t1.TRAD_DATE                  
      AND ACCT_SORT = 'RQ')
  AND t1.SEC_CDE1 IN  
   (SELECT s01.SEC_CDE
    FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
    WHERE S_DATE <= t1.TRAD_DATE
      AND E_DATE > t1.TRAD_DATE
      AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
      AND s01.SEC_CDE = s02.SEC_CDE
    )
  AND t1.SHDR_ACCT NOT IN ('B880810718','B880859746','B880969127','B880969135')  
  AND t1.SETL_VOL <> 0
  AND t1.RESULT_CDE IN ('0000')
  AND t1.RCOD_TYPE IN ('001')
  and t1.shdr_acct = t2.sec_acct
GROUP BY 1,2,3
) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;

--上交所‘融券卖出’、‘买券还券’、‘融券平仓’业务的计算（BIZ_TYPE=1103）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '1103' AS BIZ_TYPE,
    SUM(BUY_FEE_TAX + SAL_FEE_TAX) AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SELECT 
   t1.SHDR_ACCT
  ,t2.SEC_CDE1 AS SEC_CDE
  ,t1.TRAD_DATE
   ---买入数量
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'B' THEN t2.SETL_VOL
         ELSE 0
         END ) AS BUY_QTY     
   --卖出数量为负值
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'S' THEN -t2.SETL_VOL 
         ELSE 0
         END) AS SAL_QTY
   --买方清算金额为负
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'B' THEN -t2.CLR_AMT
         ELSE 0
         END) AS BUY_AMT
   --卖方清算金额为正
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'S' THEN t2.CLR_AMT
         ELSE 0
         END) AS SAL_AMT
   --买方税费为负
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'B' THEN -(STMP_TAX+HAND_FEE+TRAN_FEE+CMSN_CHG+ADMIN_CHRG+OTH_AMT1+OTH_AMT2+OTH_AMT3)
         ELSE 0
         END) AS BUY_FEE_TAX
   --卖方税费为负
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'S' THEN -(STMP_TAX+HAND_FEE+TRAN_FEE+CMSN_CHG+ADMIN_CHRG+OTH_AMT1+OTH_AMT2+OTH_AMT3)
         ELSE 0
         END) AS SAL_FEE_TAX
   --买方实际收付为负
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'B' THEN -t2.FACT_PAMT
         ELSE 0
         END) AS BUY_FACT_AMT
   --卖方实际收付为正
  ,SUM(CASE WHEN t2.TRAD_DIRC = 'S' THEN t2.FACT_PAMT
         ELSE 0
         END) AS SAL_FACT_AMT
FROM ( 
       SELECT 
          a.TRAD_DATE
         ,a.SAL_SHDR_ACCT AS SHDR_ACCT
         ,a.TRAD_NBR
         ,a.SAL_APLY_NBR AS APP_NBR
       FROM  nsOVIEW.CSDC_H_SEC_TRAD a,
          (
            SELECT PRMT_VAL AS SEC_ACCT 
            FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
            WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
          ) c
       WHERE TRAD_DATE between cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
         AND a.SAL_SHDR_ACCT LIKE 'E%'
         AND SUBSTR(a.MEMO,2,1) IN ('6') --融券卖出'
         and a.sal_shdr_acct = c.sec_acct
       UNION ALL
       SELECT
          a.TRAD_DATE
         ,a.B_SHR_ACCT AS SHDR_ACCT
         ,a.TRAD_NBR
         ,a.BUY_APLY_NBR as app_nbr
        FROM nsOVIEW.CSDC_H_SEC_TRAD a,
          (
            SELECT PRMT_VAL AS SEC_ACCT 
            FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
            WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
          ) c
        WHERE TRAD_DATE between cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
          AND a.B_SHR_ACCT LIKE 'E%'
          AND SUBSTR(a.MEMO,1,1) IN ('5','7')  --'买券还券'、'融券平仓'
          and a.b_shr_acct = c.sec_acct
) t1
INNER JOIN NSOVIEW.CSDC_H_CLR_STM_DTL  t2
  on  t2.data_date=t1.trad_date
  and t1.app_nbr=t2.APLY_NBR
  and t2.trad_nbr=t1.trad_nbr
  and t2.RESULT_CDE in ( '0000','8001')
  and t2.RCOD_TYPE in ('001','003')
WHERE t2.SEC_CDE1 IN  
   (SELECT s01.SEC_CDE
    FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
    WHERE S_DATE <= t1.TRAD_DATE
      AND E_DATE > t1.TRAD_DATE
      AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
      AND s01.SEC_CDE = s02.SEC_CDE
    )
group by 1,2,3
) RSLT
GROUP BY 1,2,3,4,10
;

.IF ERRORCODE <> 0 THEN .QUIT 12;

--上交所非交易过户 （A股）（BIZ_TYPE=2000）
--注：当TRAN_PRC=0 取当日的市值价格，否则取TRAN_PRC
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '2000' AS BIZ_TYPE,
    SUM(SAL_FEE_TAX) AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
select
   COALESCE(t1.TRANS_DATE,t2.TRANS_DATE) AS TRANS_DATE
  ,COALESCE(t1.SHDR_ACCT,t2.SHDR_ACCT) AS SHDR_ACCT
  ,COALESCE(t1.SEC_CDE,t2.SEC_CDE) AS SEC_CDE
  ,ZEROIFNULL(t2.BUY_QTY) AS BUY_QTY
  ,ZEROIFNULL(t1.SAL_QTY) AS SAL_QTY
  ,ZEROIFNULL(t2.BUY_AMT) AS BUY_AMT
  ,ZEROIFNULL(t1.SAL_AMT) AS SAL_AMT
  ,COALESCE(SAL_FEE_TAX, 0) AS SAL_FEE_TAX
from (
  SELECT    --转出
     a.ata as SHDR_ACCT
    ,a.sec_cde as SEC_CDE
    ,a.TRANS_DATE
    ,SUM(a.TRANS_VOL) as SAL_QTY
    ,SUM(a.TRANS_VOL* (case when a.TRAN_PRC <> 0 then a.TRAN_PRC else b.CLS_PRC end)) AS SAL_AMT
    ,SUM(a.TRAN_FEE+a.STMP_TAX+a.CMSN_CHG) AS SAL_FEE_TAX --手续费算在转出方
  FROM  nsOVIEW.CSDC_H_NON_TRAD_TRAN a, CMSSVIEW.SEC_QUOT b,
     (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
    ) c
  WHERE a.cap_type in ('PT')
    AND NOT a.APLY_NBR LIKE '%WY%'
    and a.ata NOT IN ('B880048866', 'B882696518')      
    and a.in_acct <> 'B880048866'                       
    and a.succ_indc='0'
    --and a.TRANS_RESN NOT IN ('I','J')   
    and a.TRANS_DATE between cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
    and a.sec_cde IN    (SELECT s01.SEC_CDE
                          FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
                          WHERE S_DATE <= a.TRANS_DATE
                          AND E_DATE > a.TRANS_DATE
                          AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
                          AND s01.SEC_CDE = s02.SEC_CDE)
    and a.TRANS_DATE = b.TRAD_DATE
    and a.SEC_CDE = b.SEC_CDE
    and a.ata = c.sec_acct
    group by 1,2,3
    ) t1
  FULL JOIN
  (select
      b.in_acct as SHDR_ACCT --转入
     ,b.sec_cde as SEC_CDE
     ,b.TRANS_DATE
     ,SUM(b.TRANS_VOL) as BUY_QTY
     ,SUM(b.TRANS_VOL*(case when b.TRAN_PRC <> 0 then b.TRAN_PRC else a.CLS_PRC end)) AS BUY_AMT 
   from NSOVIEW.CSDC_H_NON_TRAD_TRAN b,  CMSSVIEW.SEC_QUOT a,
   (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
    ) c
   where b.cap_type in ('PT') ---同上，加上限制条件
     and NOT b.APLY_NBR LIKE '%WY%'
     and b.ata NOT IN ('B880048866', 'B882696518') ----此处限制条件需要加上2015/3/18 19:02:29
     and b.in_acct <> 'B880048866'
     and b.succ_indc='0'
     --and a.TRANS_RESN NOT IN ('I','J') --是否去掉'I'还券划转'J'余券划转还待确认
    and b.TRANS_DATE between cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
    and b.sec_cde IN    (SELECT s01.SEC_CDE
                          FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
                          WHERE S_DATE <= b.TRANS_DATE
                          AND E_DATE > b.TRANS_DATE
                           AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
                          AND s01.SEC_CDE = s02.SEC_CDE)
    and b.TRANS_DATE = a.TRAD_DATE
    and b.SEC_CDE = a.SEC_CDE
    and b.in_acct = c.sec_acct
   group by 1,2,3
  ) t2
  on t1.SHDR_ACCT = t2.SHDR_ACCT
  and t1.SEC_CDE = t2.SEC_CDE
  and t1.TRANS_DATE = t2.TRANS_DATE
) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--上交所首发,以上市日期的前一天作为限制日期（BIZ_TYPE=3001）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '3001' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SELECT 
  t2.STK_CDE AS SEC_CDE,
  t2.ISS_PRC,
  t2.LIST_LAST_DATE,
  t1.SEC_ACCT_NBR AS SHDR_ACCT,
  SUM(t1.TD_END_HOLD_VOL) AS BUY_QTY,
  0 AS SAL_QTY,
  t2.ISS_PRC*SUM(t1.TD_END_HOLD_VOL) AS BUY_AMT,
  0 AS SAL_AMT 
FROM
  nspview.ACT_SEC_HOLD_HIS t1
INNER JOIN 
(
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
) t3
ON t1.SEC_ACCT_NBR = t3.SEC_ACCT
INNER JOIN
(
 SEL B.ISS_PRC,
   B.STK_CDE,
   MAX(C.calendar_date) AS LIST_LAST_DATE
 FROM
   NSPUBVIEW.MID_IPO_ISS_INFO B,
   NSOVIEW.TDSUM_DATE_EXCHANGE C
 WHERE
   C.calendar_date < B.LIST_DATE
   AND C.IS_TRD_DT='1'
 GROUP BY 1,2
 ) t2
 ON  t1.SEC_CDE = t2.STK_CDE
 AND t1.S_DATE <= t2.LIST_LAST_DATE
 AND t1.E_DATE > t2.LIST_LAST_DATE
 AND t1.MKT_SORT ='0'
 AND t2.LIST_LAST_DATE BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
 WHERE t2.STK_CDE IN (SELECT s01.SEC_CDE
                          FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
                          WHERE S_DATE <= t2.LIST_LAST_DATE
                          AND E_DATE > t2.LIST_LAST_DATE
                          AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
                          AND s01.SEC_CDE = s02.SEC_CDE)
GROUP BY 1,2,3,4
) RSLT
GROUP BY 1,2,3,4,5,10;


.IF ERRORCODE <> 0 THEN .QUIT 12;


--增发 (交易日期和上市日期一致，上交所中发行日期和万得的上市日期一样) （BIZ_TYPE=3002）
--注：不包含股权激励的部分,股权激励部分按trad_date当日的市值价格计算买入金额
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '3002' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
sel 
  t2.STK_CDE AS SEC_CDE,
  t1.SHDR_ACCT,
  t1.trad_date,
  t1.trans_vol as BUY_QTY,
  0 AS SAL_QTY,
  t2.ISS_PRC*t1.trans_vol AS BUY_AMT,
  0 AS SAL_AMT
from 
(
  SEL
    SHDR_ACCT,  
    SEC_CDE, 
    trad_date,
    SUM(trans_vol) AS trans_vol
  FROM nsOVIEW.CSDC_H_SEC_TRAN a ,
  (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
  ) b
  WHERE a.CAP_TYPE ='XL'
    AND  a.NEGT_TYPE = 'F'
    AND a.TRANS_TYPE='00F'
    AND a.TRAD_DIRC ='B'
    AND a.trad_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
    AND a.shdr_acct = b.sec_acct
  group by 1,2,3
)  t1 
inner  join 
(
  sel  
    STK_CDE
    ,ISS_DATE
    ,MAX(A.ISS_PRC) AS ISS_PRC
  from nsoview.SSE_STK_FI_INFO A
  where A.E_DATE='30001231'
  AND A.STK_CDE <> ''
  group by 1,2
) t2 
ON t1.SEC_CDE = t2.STK_CDE
AND t1.trad_date = t2.ISS_DATE
where  t2.STK_CDE IN
  (SELECT s01.SEC_CDE
    FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
    WHERE S_DATE <= t1.TRAD_DATE
    AND E_DATE > t1.TRAD_DATE
    AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
    AND s01.SEC_CDE = s02.SEC_CDE)
) RSLT
GROUP BY 1,2,3,4,5,10;


.IF ERRORCODE <> 0 THEN .QUIT 12;


--增发-股权激励（股权激励的部分价格无法匹配,取交易当天的市值价格计算买入卖出金额） （BIZ_TYPE=3003）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '3003' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SEL  
  a.SEC_CDE, 
  a.trad_date,
  a.SHDR_ACCT,
  SUM(trans_vol) AS BUY_QTY,
  SUM(trans_vol * b.CLS_PRC) AS BUY_AMT,
  0 AS SAL_QTY,
  0 AS SAL_AMT
FROM  nsOVIEW.CSDC_H_SEC_TRAN a, CMSSVIEW.SEC_QUOT b,
  (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
  ) c
WHERE a.CAP_TYPE ='XL'
  AND a.NEGT_TYPE = 'C' 
  AND a.TRANS_TYPE='00F'
  AND a.TRAD_DIRC ='B'
  AND a.trad_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
  AND a.SEC_CDE IN
    (SELECT s01.SEC_CDE
    FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
    WHERE S_DATE <= a.TRAD_DATE
    AND E_DATE > a.TRAD_DATE
    AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
    AND s01.SEC_CDE = s02.SEC_CDE)
  AND A.TRAD_DATE = B.TRAD_DATE
  AND A.SEC_CDE = B.SEC_CDE
  AND A.SHDR_ACCT = C.SEC_ACCT
group by 1,2,3
) RSLT
GROUP BY 1,2,3,4,5,10;


.IF ERRORCODE <> 0 THEN .QUIT 12;


--上交所配股 (从配股认购来算，配股的价格过户表中有) （BIZ_TYPE=4002） 
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '4002' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SEL
  t2.SEC_CDE,
  t1.trad_date,
  t2.REG_DATE,
  t1.SHDR_ACCT,
  SUM(t1.TRANS_VOL) AS BUY_QTY,
  0 AS SAL_QTY,
  SUM(t1.TRANS_VOL*t1.TRAN_PRC) AS BUY_AMT,
  0 AS SAL_AMT
FROM 
(
  SEL a.SHDR_ACCT, a.SEC_CDE, a.trad_date,TRAN_PRC,TRANS_VOL 
  FROM nsOVIEW.CSDC_H_SEC_TRAN a, 
  (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
  ) c
  WHERE a.TRANS_TYPE='00A'
    AND a.TRAD_DIRC='B'
    AND a.SHDR_ACCT NOT IN ('B880810718','B880859746','B880969127','B880969135') 
    AND a.CAP_TYPE='PG'
    AND a.trad_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
    AND A.SHDR_ACCT = C.SEC_ACCT
    AND a.sec_cde in     
        (SELECT s01.SEC_CDE
          FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
        WHERE S_DATE <= a.TRAD_DATE
        AND E_DATE > a.TRAD_DATE
        AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
        AND s01.SEC_CDE = s02.SEC_CDE)
) t1
INNER JOIN 
  (
      sel ISS_CDE,cast(SEC_CDE as char(6)) SEC_CDE,EQUT_YEARS,REG_DATE  
    from  nsoview.CSDC_H_EQT_REG  
    where reg_sort= 'PG'
    group by 1,2,3,4
  )  t2 
   ON t1.SEC_CDE = t2.ISS_CDE
   AND substr(CAST(t1.trad_date AS CHAR(8)),1,4) = t2.EQUT_YEARS
GROUP BY 1,2,3,4
) RSLT
GROUP BY 1,2,3,4,5,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


 --上交所（送股及转增股是一起的）,考虑通过关联权益登记表和持有表计算。（BIZ_TYPE=4001）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '4001' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
 SEL  
    CAST(t1.SEC_CDE AS CHAR(6))  AS  SEC_CDE
   ,t2.reg_date
   ,t1.SEC_ACCT_NBR AS SHDR_ACCT   
   ,t2.allot_numrt
   ,t2.ALLOT_DENOM
   ,CAST(sum(t1.TD_END_HOLD_VOL)  AS DECIMAL(18,0) ) as HOLD_VOL
   ,HOLD_VOL * t2.allot_numrt/(t2.ALLOT_DENOM+allot_numrt)  AS BUY_QTY
   ,0 AS SAL_QTY
   ,0 AS BUY_AMT
   ,0 AS SAL_AMT
from  nspview.ACT_SEC_HOLD_HIS t1
INNER JOIN 
  (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
  ) t3
  ON t1.sec_acct_nbr = t3.sec_acct
INNER JOIN
(
SELECT
  cast(t01.sec_cde as char(6)) sec_cde
 ,t01.reg_date
 ,t01.allot_numrt
 ,t01.ALLOT_DENOM
FROM
  nsoview.CSDC_H_EQT_REG t01
  WHERE t01.REG_SORT IN ('SG')
    AND cast(t01.sec_cde as char(6)) in   
        (SELECT s01.SEC_CDE
          FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
          WHERE S_DATE <= t01.reg_date
          AND E_DATE > t01.reg_date
          AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
          AND s01.SEC_CDE = s02.SEC_CDE)
    AND t01.RMAK_DESC NOT LIKE ('%对价%')
    AND t01.reg_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
                --AND mkup_indc = '1'
  GROUP BY 1,2,3,4
) t2
ON t1.SEC_CDE =t2.SEC_CDE
  AND t1.S_DATE <= t2.reg_date
  AND t1.E_DATE > t2.reg_date
group by 1,2,3,4,5
) RSLT
GROUP BY 1,2,3,4,5,10;


.IF ERRORCODE <> 0 THEN .QUIT 12;


--上交所红利 BIZ_TYPE=4004
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '4004' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SEL  
   CAST(t1.SEC_CDE AS CHAR(6))  AS  SEC_CDE
  ,t1.SEC_ACCT_NBR AS SHDR_ACCT      
  ,t2.CAP_rate
  ,t2.divd
  ,CAST(sum(t1.TD_END_HOLD_VOL)  AS DECIMAL(18,0) )as HOLD_VOL
  ,0 AS BUY_QTY
  ,0 AS SAL_QTY
  ,0 AS BUY_AMT
  ,t2.divd*HOLD_VOL/t2.CAP_rate  AS SAL_AMT --红利金额
from  nspview.ACT_SEC_HOLD_HIS t1
INNER JOIN 
  (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
  ) t3
  ON t1.sec_acct_nbr = t3.sec_acct
  INNER JOIN 
  (
    SELECT
            t1.sec_cde
            ,'0' AS mkt_type
            ,t1.reg_date
            ,t1.divd
            ,CASE WHEN t2.allot_numrt IS NULL 
              THEN 1 
              ELSE 1+t2.allot_numrt/t2.ALLOT_DENOM 
             END AS CAP_rate
        FROM
            (
                SELECT
                cast(t1.sec_cde as char(6)) sec_cde
                ,t1.reg_date
                ,t1.list_date
                ,t1.bef_tax_divd/100  AS divd
            FROM
                nsoview.CSDC_H_EQT_REG  t1
            WHERE
                cast(t1.sec_cde as char(6)) in 
                (SELECT s01.SEC_CDE
                  FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
                  WHERE S_DATE <= t1.reg_date
                  AND E_DATE > t1.reg_date
                  AND SEC_REG_STS_SORT NOT IN ('2','5')            --证券登记状态类别 2：退市、5：废弃
                  AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
                  AND s01.SEC_CDE = s02.SEC_CDE)
                AND t1.EQUT_TYPE IN ('HL')
                AND t1.RMAK_DESC NOT LIKE ('%对价%')
                AND t1.reg_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
                AND t1.MKUP_INDC = '1' -- 新添加字段，限定'沪股通'相关因素的影响
            GROUP BY 1,2,3,4
            )t1
            LEFT OUTER JOIN
            (SELECT
                cast(t1.sec_cde as char(6)) sec_cde
                ,t1.reg_date
                ,t1.allot_numrt
                ,t1.ALLOT_DENOM
            FROM
                nsoview.CSDC_H_EQT_REG t1
            WHERE
                cast(t1.sec_cde as char(6)) in 
                (SELECT s01.SEC_CDE
                  FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
                  WHERE S_DATE <= t1.reg_date
                  AND E_DATE > t1.reg_date
                  AND SEC_REG_STS_SORT NOT IN ('2','5')            --证券登记状态类别 2：退市、5：废弃
                  AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
                  AND s01.SEC_CDE = s02.SEC_CDE)
                AND t1.REG_SORT IN ('SG')
                AND t1.RMAK_DESC NOT LIKE ('%对价%')
                AND t1.reg_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')
                --AND mkup_indc = '1'
            GROUP BY 1,2,3,4
            )t2
            ON t1.sec_cde = t2.sec_cde 
            AND t1.reg_date = t2.reg_date
        GROUP BY 1,2,3,4,5
  ) t2
  ON t1.SEC_CDE =t2.SEC_CDE
  AND t1.S_DATE <= t2.reg_date
  AND t1.E_DATE > t2.reg_date
group by 1,2,3,4
) RSLT
GROUP BY 1,2,3,4,5,10;


.IF ERRORCODE <> 0 THEN .QUIT 12;

--上交所可转债转股 （与上交所网站完全一致） BIZ_TYPE=5000
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '5000' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SELECT 
  a.TRAD_DATE,
  b.SHDR_ACCT,
  b.SEC_CDE,
  SUM(b.TRANS_VOL) AS BUY_QTY, --债券转股票
  0 AS SAL_QTY,
  SUM(b.TRANS_VOL* b.TRAN_PRC) AS BUY_AMT,
  0 AS SAL_AMT FROM 
  (
    select * from  nsoview.csdc_h_sec_tran t1,
     (
       SELECT PRMT_VAL AS SEC_ACCT 
       FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
       WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
     ) t3	
    where TRANS_TYPE='00Y' 
	  and CAP_TYPE='GZ' 
	  and TRAD_DIRC='S'
      and TRAD_DATE BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD') 
	  and t1.shdr_acct = t3.sec_acct
  )  a
  inner join 
 (
   select * from nsoview.csdc_h_sec_tran  t1,
     (
       SELECT PRMT_VAL AS SEC_ACCT 
       FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
       WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
     ) t3
   where TRANS_TYPE='00Y' 
     and CAP_TYPE='PT' 
	 and TRAD_DIRC='B' 
     and TRAD_DATE BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD') 
	 and t1.shdr_acct = t3.sec_acct
 ) b
on  a.TRAD_DATE =b.TRAD_DATE
and a.TRAD_NBR =b.TRAD_NBR
and a.APLY_NBR=b.APLY_NBR
and a.TRAD_TIME=b.TRAD_TIME
WHERE b.SEC_CDE IN
     (SELECT s01.SEC_CDE
        FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
        WHERE S_DATE <= a.trad_date
        AND E_DATE > a.trad_date
        AND SEC_REG_STS_SORT NOT IN ('2','5')            --证券登记状态类别 2：退市、5：废弃
        AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
        AND s01.SEC_CDE = s02.SEC_CDE)
group  by 1,2,3
) RSLT
GROUP BY 1,2,3,4,5,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;

---- 沪市ETF申赎(从过户表中取申购赎回的数量，再乘以市值价格，计算买入和卖出金额) BIZ_TYPE=6000
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '0' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '6000' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SELECT
     k1.SHDR_ACCT
    ,k1.TRAD_DATE
    ,k1.SEC_CDE
    ,SUM(CASE WHEN k1.trad_dirc = 'B' THEN k1.trans_vol  ELSE 0.00  END)  AS BUY_QTY
    ,SUM(CASE WHEN k1.trad_dirc = 'S' THEN k1.trans_vol  ELSE 0.00  END) AS SAL_QTY
    ,SUM(CASE WHEN k1.trad_dirc = 'B' THEN k1.trans_vol*t4.CLS_PRC ELSE 0.00  END)  AS BUY_AMT
    ,SUM(CASE WHEN k1.trad_dirc = 'S' THEN k1.trans_vol*t4.CLS_PRC ELSE 0.00  END) AS SAL_AMT
FROM
    NsoVIEW.CSDC_H_SEC_TRAN k1, --沪_证券成交表：dwbview.evt_h_trad_a_src
     (
       SELECT PRMT_VAL AS SEC_ACCT 
       FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
       WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
     ) t3,
	 CMSSVIEW.SEC_QUOT t4
WHERE
    cap_type = 'PT'
	AND k1.shdr_acct = t3.sec_acct
    AND trans_type IN ('007') --ETF申购赎回
    AND trans_vol <> 0 --AND tran_prc <> 0
    AND k1.trad_date BETWEEN cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
                       AND cast('$PARAM{'e_date'}' as DATE format 'YYYYMMDD')  
    AND k1.SHDR_ACCT NOT IN ('B880810718','B880859746','B880969127','B880969135') 
    AND k1.SEC_CDE 	IN
    (SELECT s01.SEC_CDE
        FROM NSOVIEW.CSDC_INTG_SEC_INFO s01, $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ s02     
        WHERE S_DATE <= k1.trad_date
        AND E_DATE > k1.trad_date
        AND SEC_REG_STS_SORT NOT IN ('2','5')            --证券登记状态类别 2：退市、5：废弃
        AND s02.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
        AND s01.SEC_CDE = s02.SEC_CDE)
	AND k1.trad_date = t4.trad_date
	AND k1.sec_cde = t4.sec_cde
GROUP BY 1,2,3
) RSLT
GROUP BY 1,2,3,4,5,10;


.IF ERRORCODE <> 0 THEN .QUIT 12;

.QUIT;

