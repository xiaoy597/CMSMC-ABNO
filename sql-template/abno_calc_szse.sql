.WIDTH 256;
.LOGON $PARAM{'HOSTNM'}/$PARAM{'USERNM'},$PARAM{'PASSWD'};

DELETE FROM $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL 
WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
AND SEC_EXCH_CDE = '1';

CREATE VOLATILE MULTISET TABLE VT_ABNO_SZSE_SEC AS(
	SELECT B.SEC_CDE
	FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_OBJ A, NSOVIEW.CSDC_INTG_SEC_INFO B
	WHERE A.ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
	AND A.SEC_CDE = B.SEC_CDE
	AND B.S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
	AND B.E_DATE > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
	AND B.MKT_SORT = '1'
) WITH DATA UNIQUE PRIMARY INDEX (SEC_CDE)
ON COMMIT PRESERVE ROWS;

.IF ERRORCODE <> 0 THEN .QUIT 12;

COLLECT STATISTICS COLUMN SEC_CDE ON VT_ABNO_SZSE_SEC;

.IF ERRORCODE <> 0 THEN .QUIT 12;

CREATE VOLATILE MULTISET TABLE VT_ABNO_SEC_ACCT AS (
    SELECT PRMT_VAL AS SEC_ACCT 
    FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_INVST
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}' AND PRMT_TYPE = '1'
) WITH DATA UNIQUE PRIMARY INDEX (SEC_ACCT)
ON COMMIT PRESERVE ROWS;

.IF ERRORCODE <> 0 THEN .QUIT 12;

COLLECT STATISTICS COLUMN SEC_ACCT ON VT_ABNO_SEC_ACCT;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所 普通交易过户 （A股） （包含信用账户的交易过户） 
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '1000' AS BIZ_TYPE,
    SUM(BUY_FEE_TAX + SAL_FEE_TAX) AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    SUM(BUY_AMT) AS BUY_AMT,
    SUM(SAL_AMT) AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
SELECT 
   TRAD_DATE
  ,t3.SEC_CDE
  ,t1.SHDR_ACCT AS SHDR_ACCT
  ,SUM(t1.BUY_VOL)  AS BUY_QTY
  ,SUM(t1.SAL_VOL)  AS SAL_QTY
  ,SUM(t1.BUY_AMT)   AS BUY_AMT
  ,SUM(t1.SAL_AMT)   AS SAL_AMT
  ,SUM(ZEROIFNULL(BUY_HAND_FEE)+ZEROIFNULL(BUY_STMP_TAX)+ZEROIFNULL(BUY_TRAN_FEE)+ZEROIFNULL(BUY_CMSN_CHG)) AS BUY_FEE_TAX
  ,SUM(ZEROIFNULL(SAL_HAND_FEE)+ZEROIFNULL(SAL_STMP_TAX)+ZEROIFNULL(SAL_TRAN_FEE)+ZEROIFNULL(SAL_CMSN_CHG))  AS SAL_FEE_TAX
FROM NSOVIEW.CSDC_S_CLR_TRANS_TRAD t1,
    VT_ABNO_SEC_ACCT t2, VT_ABNO_SZSE_SEC t3
WHERE
  t1.shdr_acct = t2.sec_acct 
  AND t1.TRAD_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')           
  --去掉融券专用账户
  AND t1.SHDR_ACCT NOT IN 
   (
    SELECT DISTINCT SEC_LN_BROKER_ACCT
    FROM NSOVIEW.CSDC_S_CRDT_TRAD_SEAT_ACCT_RLTN_HIS                     
    WHERE S_DATE <= t1.trad_date 
      AND E_DATE > t1.trad_date)
  AND SHDR_ACCT <> '0899999004' --中国证券登记结算深圳分公司证券集中交收账户
  AND t1.SEC_CDE = CAST(t3.SEC_CDE AS INT)
GROUP BY 1,2,3
) RSLT
GROUP BY 1,2,3,4,10
;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所非交易过户（A股）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '2000' AS BIZ_TYPE,
    0 AS TAX_FEE,
    SUM(BUY_QTY) AS BUY_VOL,
    SUM(SAL_QTY) AS SAL_VOL,
    0 AS BUY_AMT,
    0 AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM (
--5月1号前
select 		
   t1.shdr_acct  as SHDR_ACCT
  ,'1'          as MKT_SORT
  ,t3.SEC_CDE AS SEC_CDE
  ,SUM(CASE WHEN chg_vol>0 THEN t1.chg_vol ELSE 0 END) AS buy_qty--买               
  ,SUM(CASE WHEN chg_vol<0 THEN ABS(t1.chg_vol) ELSE 0 END) AS sal_qty --卖 
from nsoview.CSDC_S_SHDR_HLD_CHG t1,
    VT_ABNO_SEC_ACCT t2, VT_ABNO_SZSE_SEC t3
where t1.shdr_acct = t2.sec_acct
  and t1.chg_cde in ( 'A0A','AOC','A4A','A69','A72','A76','A77','A89','R04','R05','R06')                               
  and t1.chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
  and t1.SEC_CDE = CAST(t3.SEC_CDE AS INT)
  group by 1,2,3
  union all
--2017年5月后计算方法
select 		
  t1.shdr_acct  as SHDR_ACCT
  ,'1'          as MKT_SORT
  ,t3.SEC_CDE AS SEC_CDE
  ,SUM(CASE WHEN chg_vol>0 THEN chg_vol ELSE 0 END) AS buy_qty--买               
  ,SUM(CASE WHEN chg_vol<0 THEN ABS(chg_vol) ELSE 0 END) AS sal_qty --卖 
from   nsoview.CSDC_S_STK_CHG t1,
    VT_ABNO_SEC_ACCT t2, VT_ABNO_SZSE_SEC t3
where t1.shdr_acct = t2.sec_acct
  and t1.chg_cde in ( 'A0A','AOC','A4A','A69','A72','A76','A77','A89','R04','R05','R06')                               
  and t1.chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
  and t1.SEC_CDE = t3.SEC_CDE
  group by 1,2,3
) RSLT
GROUP BY 1,2,3,4,10
;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所首发（A股） 与万得的发行总股本对，没问题
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
select 
  CAST(aa.SEC_ACCT_NBR  AS CHAR(10))as SHDR_ACCT,
  aa.SEC_CDE  AS  SEC_CDE,             
  CAST(sum(aa.TD_END_HOLD_VOL)  AS DECIMAL(18,0) )as BUY_QTY,
  0 as SAL_QTY,
  CAST(sum(aa.TD_END_HOLD_VOL*bb.ISS_PRC) AS DECIMAL(18,0) ) AS BUY_AMT,
  0  AS SAL_AMT   
  from  nsPVIEW.ACT_SEC_HOLD_HIS aa
  INNER JOIN 
  (
	SELECT A.STK_CDE,A.LIST_DATE,A.ISS_PRC,MAX(calendar_date) AS LIST_LAST_DATE
	FROM  nspubview.MID_IPO_ISS_INFO A, 
		  nsoview.tdsum_date_exchange  B 
	WHERE B.calendar_date <A.LIST_DATE
	  AND B.is_trd_dt =1
	group by 1,2,3
  ) bb
  ON aa.SEC_CDE = bb.STK_CDE
  INNER JOIN
    VT_ABNO_SEC_ACCT cc
  on aa.sec_acct_nbr = cc.sec_acct
  INNER JOIN VT_ABNO_SZSE_SEC dd
  on aa.SEC_CDE = dd.SEC_CDE
  WHERE bb.LIST_LAST_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
    AND aa.s_date <= CAST(bb.LIST_LAST_DATE AS DATE FORMAT 'YYYYMMDD') 
    AND aa.e_date >CAST(bb.LIST_LAST_DATE AS DATE FORMAT 'YYYYMMDD')
	and aa.MKT_SORT ='1'
	group by 1,2
) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所增发
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
-- 五月份前定向增发，不含股权激励
sel 
  t1.shdr_acct,
  t1.chg_date,
  t2.STK_CDE as sec_cde,
  t2.FI_LIST_DATE,
  t2.ISS_PRC,
  sum(t1.chg_vol) AS BUY_QTY,
  0 AS SAL_QTY,
  sum(t1.chg_vol*t2.ISS_PRC) AS BUY_AMT,
  0 AS SAL_AMT
from 
  (
   sel shdr_acct, chg_date,t2.sec_cde ,chg_vol 
   from  
     nsoview.CSDC_S_SHDR_HLD_CHG t1, VT_ABNO_SZSE_SEC t2, VT_ABNO_SEC_ACCT t3
   where  chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
     and chg_cde ='A30'
	 and STK_CHRC <> '02'
	 AND SHDR_ACCT <> '0899999004'
	 and t1.shdr_acct = t3.sec_acct
	 and t1.sec_cde = CAST(t2.SEC_CDE AS INT)
   )  t1 INNER JOIN
  (	
   SELECT A.STK_CDE,A.FI_LIST_DATE,A.ISS_PRC,MAX(calendar_date) AS LIST_LAST_DATE ,MAX(ISS_PRC)  AS FIN_ISS_PRC
   FROM NSOVIEW.szse_stk_fi_info A, 
		nsoview.tdsum_date_exchange  B 
   WHERE B.calendar_date <A.FI_LIST_DATE
     AND B.is_trd_dt =1
	 AND A.FI_LIST_DATE  BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')   
   group by 1,2,3
   ) t2 
   on t1.sec_cde = t2.STK_CDE
   and t1.chg_date = t2.LIST_LAST_DATE
   group  by 1,2,3,4,5
union all
-- 五月份后定向增发，不含股权激励
sel 
  t1.shdr_acct,
  t1.chg_date,
  t2.STK_CDE as sec_cde,
  t2.FI_LIST_DATE,
  t2.ISS_PRC,
  sum(t1.chg_vol) AS BUY_QTY,
  0 AS SAL_QTY,
  sum(t1.chg_vol*t2.ISS_PRC) AS BUY_AMT,
  0 AS SAL_AMT
from 
  (
   sel shdr_acct, chg_date, t2.sec_cde ,chg_vol from  
	   nsoview.CSDC_S_STK_CHG t1, VT_ABNO_SZSE_SEC t2, VT_ABNO_SEC_ACCT t3
	   where  chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
	     and chg_cde ='A44'
	     and STK_CHRC <> '02'
		 AND SHDR_ACCT <> '0899999004'
		 and t1.shdr_acct = t3.sec_acct
		 and t1.sec_cde = t2.SEC_CDE
   )  t1 
   INNER JOIN 
  (	
   SELECT A.STK_CDE,A.FI_LIST_DATE,A.ISS_PRC,MAX(calendar_date) AS LIST_LAST_DATE ,MAX(ISS_PRC)  AS FIN_ISS_PRC
   FROM NSOVIEW.szse_stk_fi_info A, 
	    nsoview.tdsum_date_exchange  B 
   WHERE B.calendar_date <A.FI_LIST_DATE
     AND  B.is_trd_dt =1
	 AND A.FI_LIST_DATE  BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')   
   group by 1,2,3
   ) t2 
   on t1.sec_cde =t2.STK_CDE
   and t1.chg_date = t2.LIST_LAST_DATE
   group  by 1,2,3,4,5
) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所增发（股权激励）
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
-- 股权激励五月份前，取chg_date当日的市值价格乘以BUY_QTY，计算买入价格
sel 
  t1.shdr_acct, t1.chg_date,
  t4.sec_cde AS SEC_CDE,
  sum(t1.chg_vol) AS BUY_QTY,
  sum(t1.chg_vol * t2.CLS_PRC) as BUY_AMT,
  0 AS SAL_QTY,
  0 AS SAL_AMT
from 
  nsoview.CSDC_S_SHDR_HLD_CHG t1 , CMSSVIEW.SEC_QUOT t2, 
  VT_ABNO_SEC_ACCT t3, VT_ABNO_SZSE_SEC t4
where chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
  and chg_cde ='A30'
  and STK_CHRC = '02' 
  AND SHDR_ACCT <> '0899999004'
  and t4.sec_cde = t2.sec_cde
  and t1.chg_date = t2.trad_date
  and t1.shdr_acct = t3.sec_acct
  and t1.sec_cde = CAST(t4.sec_cde as int)
group  by 1,2,3
union all
-- 股权激励五月份后，取chg_date当日的市值价格乘以BUY_QTY，计算买入价格
sel
  t1.shdr_acct, 
   t1.chg_date,
  t1.SEC_CDE,
  sum(t1.chg_vol) AS BUY_QTY,
  sum(t1.chg_vol * t2.CLS_PRC) as BUY_AMT,
  0 AS SAL_QTY,
  0 AS SAL_AMT
from 
  nsoview.CSDC_S_STK_CHG t1  , CMSSVIEW.SEC_QUOT t2, 
  VT_ABNO_SEC_ACCT t3, VT_ABNO_SZSE_SEC t4
where chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
  and chg_cde ='A44'
  and STK_CHRC = '02'
  AND SHDR_ACCT <> '0899999004'
  and t1.SEC_CDE = t2.sec_cde
  and t1.chg_date = t2.trad_date
  and t1.sec_cde = t4.sec_cde
  and t1.shdr_acct = t3.sec_acct
  group  by 1,2,3
) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所配股逻辑
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
 t1.shdr_acct,
 t1.chg_date,
 t1.sec_cde as sec_cde,
 t2.RIGHT_ARRV_DATE,
 t2.SUBSC_PRC,
 SUM(t1.chg_vol) AS BUY_QTY,
 SUM(t2.SUBSC_PRC*t1.chg_vol) AS BUY_AMT,
 0 AS SAL_QTY,
 0 AS SAL_AMT
 FROM 
 (
 SEL a.shdr_acct, a.chg_date, a.chg_vol, c.sec_cde 
 FROM nsoview.CSDC_S_SHDR_HLD_CHG a,  VT_ABNO_SEC_ACCT b, VT_ABNO_SZSE_SEC c
 WHERE  a.chg_cde='A42'
 AND chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
 and a.shdr_acct = b.sec_acct
 and a.sec_cde = cast(c.sec_cde as int)
 ) t1,
 nsoview.csdc_s_right_prmt_his t2
 WHERE t2.CONV_SEC_CDE = t1.sec_cde
   AND t1.chg_date = t2.RIGHT_ARRV_DATE 
   AND t2.SUBSC_PRC <>0
   AND t2.E_DATE =cast('30001231' as date format 'YYYYMMDD')
 GROUP BY 1,2,3,4,5
 UNION ALL
 SEL t1.shdr_acct, 
	t1.chg_date,
	t2.CONV_SEC_CDE as sec_cde,
	t2.RIGHT_ARRV_DATE,
	t2.SUBSC_PRC,
	SUM(t1.chg_vol) as BUY_QTY,
	SUM(t2.SUBSC_PRC*t1.chg_vol) AS BUY_AMT,
	0 AS SAL_QTY,
	0 AS SAL_AMT
 FROM 
 (
 SEL a.shdr_acct, a.chg_date, a.chg_vol, c.sec_cde  
 FROM nsoview.CSDC_S_stk_chg a,  VT_ABNO_SEC_ACCT b, VT_ABNO_SZSE_SEC c
 WHERE   a.chg_cde='A42'
 AND chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
 and a.shdr_acct = b.sec_acct
 and a.sec_cde = c.sec_cde
 ) t1,
 nsoview.csdc_s_right_prmt_his t2
 WHERE t2.CONV_SEC_CDE = t1.sec_cde
   AND t1.chg_date = t2.RIGHT_ARRV_DATE 
   AND t2.SUBSC_PRC <>0
   AND t2.E_DATE =cast('30001231' as date format 'YYYYMMDD')
 GROUP BY 1,2,3,4,5
 ) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--深交所（送股、转增）2017年5月份前，送、转增股的股份变动日期和公告上的股权登记日期一致
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
select 		
   a.shdr_acct  as SHDR_ACCT
  ,'1'          as MKT_SORT
  ,c.sec_cde AS SEC_CDE
  ,sum(a.chg_vol) as BUY_QTY
  ,0 AS BUY_AMT
  ,0 AS SAL_QTY
  ,0 AS SAL_AMT
from   nsoview.CSDC_S_SHDR_HLD_CHG a, 
  VT_ABNO_SEC_ACCT b, VT_ABNO_SZSE_SEC c
where a.chg_cde in ( 'A40','A39')                               
  and a.chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
  and a.shdr_acct = b.sec_acct
  and a.sec_cde = cast(c.sec_cde as int)
  group by 1,2,3
union all
--深交所（送股、转增）2017年5月份后
select 		
  a.shdr_acct  as SHDR_ACCT
  ,'1'          as MKT_SORT
  ,c.SEC_CDE
  ,sum(a.chg_vol) as BUY_QTY
  ,0 AS BUY_AMT
  ,0 AS SAL_QTY
  ,0 AS SAL_AMT
from   nsoview.CSDC_S_STK_CHG a,
  VT_ABNO_SEC_ACCT b, VT_ABNO_SZSE_SEC c 
where a.chg_cde in ( 'A40','A39')                               
  and a.chg_date BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
  and a.shdr_acct = b.sec_acct
  and a.sec_cde = c.sec_cde
group by 1,2,3
 ) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;

--深交所分红
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
  t1.sec_acct_nbr as shdr_acct,
  t2.SEC_CDE AS SEC_CDE
  ,t2.BEF_TAX_RATE_NUMRT
  ,t2.BEF_TAX_RATE_DENOM
  ,t2.EQUITY_REG_DATE
  ,sum(t1.TD_END_HOLD_VOL)   as hld_vol
  ,0 AS BUY_QTY
  ,0 AS BUY_AMT
  ,0 AS SAL_QTY
  ,t2.BEF_TAX_RATE_NUMRT/t2.BEF_TAX_RATE_DENOM* hld_vol AS SAL_AMT
FROM
(
  SEL a.sec_acct_nbr, a.td_end_hold_vol, a.sec_cde, a.s_date, a.e_date 
  FROM  
  NSPVIEW.ACT_SEC_HOLD_HIS a, 
  VT_ABNO_SEC_ACCT b, VT_ABNO_SZSE_SEC c
  where MKT_SORT = '1' 
    AND S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
    AND E_DATE > CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
	and a.sec_acct_nbr = b.sec_acct
	and a.sec_cde = c.sec_cde
)  t1
RIGHT JOIN
(
  SELECT 
    B.EQUT_YEARLY,
    B.SEC_CDE,
    B.EQUITY_REG_DATE,
    A.STK_CHRC,
    A.BEF_TAX_RATE_NUMRT,
    A.BEF_TAX_RATE_DENOM 
  FROM NSOVIEW.CSDC_S_COMP_ACT_DIVD_PRMT_HIS  A 
	  ,NSOVIEW.CSDC_S_COMP_ACT_EQUT_PRMT_HIS  B 
  where A.BIZ_NBR =B.BIZ_NBR  
    and A.E_DATE='30001231' 
    and B.E_DATE='30001231'  
    and A.PRCS_STS='Y' 
    AND A.EQUT_SORT='HL'
	AND B.EQUITY_REG_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
	AND A.STK_CHRC = '00'
	AND B.SEC_CDE IN
  		(SELECT SEC_CDE FROM VT_ABNO_SZSE_SEC)
) t2
ON  t1.sec_cde = t2.sec_cde
AND t1.S_DATE <= t2.EQUITY_REG_DATE
AND t1.e_DATE > t2.EQUITY_REG_DATE
group by 1,2,3,4,5
 ) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


--可转债转股
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
--深市2017年5月之前
	select
	a.shdr_acct
    ,a.PRCS_DATE
	,b.CONV_PRC AS CONV_PRC
	,d.sec_cde AS SEC_CDE
    ,sum(a.conv_vol) as BUY_QTY
	,SUM(a.conv_vol*b.CONV_PRC) AS BUY_AMT
	,0 AS SAL_QTY
	,0 AS SAL_AMT
from nsodata.CSDC_S_CONV_BOND_TRAD  a
inner join nsodata.CSDC_S_CONV_BOND_REG  b
        on  a.CONV_BOND_CDE = b.CONV_BOND_CDE
       and b.s_date<= a.PRCS_DATE and b.e_date> a.PRCS_DATE
inner join VT_ABNO_SEC_ACCT c
	   on a.shdr_acct = c.sec_acct
inner join VT_ABNO_SZSE_SEC d
		on b.sec_cde = cast(d.sec_cde as int)
where a.BIZ_SORT in ('30','31','32')  --30 可转债转股，31可转债有条件强制转股，32可转债无条件强制转股
  and a.PRCS_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
group by 1,2,3,4
union all
--深市2017年5月之后
sel t1.shdr_acct,
	t1.TRAD_DATE,
	t2.cls_prc as conv_prc,   -- 此处存疑，暂时用收盘价（刘超）
	t1.SEC_CDE,
	sum(SETL_VOL) as BUY_QTY,
	sum(SETL_VOL * T2.CLS_PRC) as BUY_AMT,
	0 as SAL_QTY,
	0 as SAL_AMT
from NSOVIEW.CSDC_S_DTL_RESULT t1, CMSSVIEW.SEC_QUOT t2,
  VT_ABNO_SEC_ACCT t3, VT_ABNO_SZSE_SEC t4
where 
	BIZ_SORT='ZQZG'  
	AND t1.TRAD_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
	and t1.sec_cde = t2.sec_cde
	and t1.trad_date = t2.trad_date
	and t1.shdr_acct = t3.sec_acct
	and t1.SEC_CDE = t4.sec_cde
	AND  SETL_INDC='Y'
    AND SETL_VOL>0
	--and STK_CHRC<>'02'  --'00'：无限售流通股；'01'：IPO后限售股；'02'：股权激励限售股；'05'：IPO前限售股。
	 -- and substr(CSTD_UNIT,1,3) != '999' --999是质押业务托管单元，需要去掉
	group by 1,2,3,4
 ) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;

---- 深市ETF申赎 (乘以市值价格，计算买入和卖出金额)
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
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
   t1.SHDR_ACCT
  ,t1.CHG_DATE AS CHG_DATE
  ,t4.sec_cde AS SEC_CDE
  ,SUM(CASE WHEN chg_vol>0 THEN t1.chg_vol ELSE 0 END) AS BUY_QTY         -- 申购       
  ,SUM(CASE WHEN chg_vol>0 THEN t1.chg_vol*t2.cls_prc ELSE 0 END) AS BUY_AMT         -- 申购       
  ,SUM(CASE WHEN chg_vol<0 THEN ABS(t1.chg_vol) ELSE 0 END) AS SAL_QTY    -- 赎回
  ,SUM(CASE WHEN chg_vol<0 THEN ABS(t1.chg_vol*t2.cls_prc) ELSE 0 END) AS SAL_AMT    -- 赎回
FROM
   nsoview.CSDC_S_SHDR_HLD_CHG t1, CMSSVIEW.SEC_QUOT t2,
  VT_ABNO_SEC_ACCT t3, VT_ABNO_SZSE_SEC t4
WHERE
   CHG_DATE BETWEEN CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') 
                   AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
   AND CHG_CDE IN ('A88','A91','A92')
   AND t1.SHDR_ACCT <> '0899999004' --中国证券登记结算深圳分公司证券集中交收账户
   and t1.shdr_acct = t3.sec_acct
   and t1.chg_date = t2.trad_date
   and t1.SEC_CDE = cast(t4.sec_cde as int)
   and t2.sec_cde = t4.sec_cde
   GROUP BY 1,2,3
 ) RSLT
GROUP BY 1,2,3,4,10;

.IF ERRORCODE <> 0 THEN .QUIT 12;


-- 股份变动差额补齐
INSERT INTO $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
SELECT
    '1' AS SEC_EXCH_CDE,
    SHDR_ACCT AS SEC_ACCT,
    SEC_CDE AS SEC_CDE,
    '9999' AS BIZ_TYPE,
    0 AS TAX_FEE,
    BUY_QTY AS BUY_VOL,
    SAL_QTY AS SAL_VOL,
    BUY_AMT AS BUY_AMT,
    SAL_AMT AS SAL_AMT,
    '$PARAM{'abno_incm_calc_btch'}' AS ABNO_INCM_CALC_BTCH
FROM 
(
SELECT 
T1.SEC_CDE, 
T1.SEC_ACCT AS SHDR_ACCT,
CASE WHEN T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL > CHG_VOL THEN 
	(T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL - T1.CHG_VOL)  ELSE 0 END AS BUY_QTY,
CASE WHEN T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL > CHG_VOL THEN 
	(T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL - T1.CHG_VOL) * CALC_S_PRC ELSE 0 END AS BUY_AMT,
CASE WHEN T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL < CHG_VOL THEN 
	(T1.CHG_VOL - (T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL))  ELSE 0 END AS SAL_QTY,
CASE WHEN T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL < CHG_VOL THEN 
	(T1.CHG_VOL - (T4.TD_END_HOLD_VOL - T3.TD_END_HOLD_VOL)) * CALC_E_PRC ELSE 0 END AS SAL_AMT
FROM
(
	SELECT
		SEC_CDE
		,SEC_ACCT
		,SUM(BUY_VOL - SAL_VOL) AS CHG_VOL
	FROM CMSSDATA.MID_ABNO_INCM_CACL_DTL
	WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
	AND SEC_EXCH_CDE = '1'
	GROUP BY SEC_CDE, SEC_ACCT
) T1, 
(
SELECT TT1.SEC_CDE, 
TT1.CALC_S_DATE, 
TT2.CLS_PRC AS CALC_S_PRC,
TT1.CALC_E_DATE, 
TT3.CLS_PRC AS CALC_E_PRC
FROM
(
  SELECT SEC_CDE,
  CASE WHEN MIN_TRAD_DATE > S_TRD_DATE THEN MIN_TRAD_DATE ELSE S_TRD_DATE END AS CALC_S_DATE,
  CASE WHEN MAX_TRAD_DATE < E_TRD_DATE THEN MAX_TRAD_DATE ELSE E_TRD_DATE END AS CALC_E_DATE
  FROM
    (
      SELECT SEC_CDE, MIN(TRAD_DATE) MIN_TRAD_DATE, MAX(TRAD_DATE) MAX_TRAD_DATE 
      FROM CMSSVIEW.SEC_QUOT 
      GROUP BY SEC_CDE
    ) TA,
    (
      SELECT S_TRD_DATE, E_TRD_DATE
      FROM
      (
         SELECT MAX(CALENDAR_DATE) AS E_TRD_DATE 
         FROM NSOVIEW.TDSUM_DATE_EXCHANGE 
         WHERE IS_TRD_DT = '1' AND CALENDAR_DATE <= cast('$PARAM{'e_date'}' AS DATE format 'YYYYMMDD') 
       ) T1,
       (
         SELECT MIN(CALENDAR_DATE) AS S_TRD_DATE 
         FROM NSOVIEW.TDSUM_DATE_EXCHANGE 
         WHERE IS_TRD_DT = '1' AND CALENDAR_DATE >= cast('$PARAM{'s_date'}' AS DATE format 'YYYYMMDD') 
       ) T2
    ) TB
) TT1, CMSSVIEW.SEC_QUOT TT2, CMSSVIEW.SEC_QUOT TT3
WHERE TT1.SEC_CDE = TT2.SEC_CDE
AND TT1.SEC_CDE = TT3.SEC_CDE
AND TT1.CALC_S_DATE = TT2.TRAD_DATE
AND TT1.CALC_E_DATE = TT3.TRAD_DATE
) T2, 
NSPVIEW.ACT_SEC_HOLD_HIS T3, NSPVIEW.ACT_SEC_HOLD_HIS T4
WHERE T1.SEC_CDE = T2.SEC_CDE
AND T1.SEC_CDE = T3.SEC_CDE
AND T1.SEC_CDE = T4.SEC_CDE
AND T1.SEC_ACCT = T3.SEC_ACCT_NBR
AND T1.SEC_ACCT = T4.SEC_ACCT_NBR
AND T3.S_DATE <= T2.CALC_S_DATE
AND T3.E_DATE > T2.CALC_S_DATE
AND T4.S_DATE <= T2.CALC_E_DATE
AND T4.E_dATE > T2.CALC_E_DATE
) RSLT
;

.IF ERRORCODE <> 0 THEN .QUIT 12;



.QUIT;

