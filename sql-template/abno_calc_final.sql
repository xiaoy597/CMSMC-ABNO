.WIDTH 256;
.LOGON $PARAM{'HOSTNM'}/$PARAM{'USERNM'},$PARAM{'PASSWD'};

DELETE FROM $PARAM{'CMSSDB'}.ABNO_INCM_CALC_RESULT 
WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
;

INSERT INTO $PARAM{'CMSSDB'}.ABNO_INCM_CALC_RESULT
SELECT
TB1.SEC_EXCH_CDE AS SEC_EXCH_CDE
,TB1.SEC_ACCT AS SEC_ACCT
,TB1.SEC_CDE AS SEC_CDE
,TB2.OAP_ACCT_NBR AS OAP_ACCT_NBR
,TB2.SEC_ACCT_NAME AS ACCT_NAME
,COALESCE(TB3.CLSF_2, '') AS CLSF_2
,COALESCE(TB3.CLSF_3, '') AS CLSF_3
,CASE WHEN TB5.OAP_ACCT_NBR IS NOT NULL THEN '1' ELSE '0' END AS IS_ODS
,CASE WHEN TB7.OAP_ACCT_NBR IS NOT NULL THEN '1' ELSE '0' END AS IS_TOP10_SHDR
,CASE WHEN TB6.SHDR_ACCT IS NOT NULL THEN '1' ELSE '0' END AS IS_LIFT_BAN_LMT_SHDR
,TB4.START_BAL AS START_HLD_MKT_VAL
,TB4.END_BAL AS END_HLD_MKT_VAL
,SUM(BUY_AMT) AS BUY_AMT
,SUM(SAL_AMT) AS SAL_AMT
,SUM(CASE WHEN BIZ_TYPE = '2000' THEN SAL_AMT ELSE 0 END) AS NON_TRAD_TRAN_INCM_AMT
,SUM(CASE WHEN BIZ_TYPE = '2000' THEN BUY_AMT ELSE 0 END) AS NON_TRAD_TRAN_EXPDT_AMT
,SUM(CASE WHEN BIZ_TYPE = '9999' THEN BUY_AMT+SAL_AMT ELSE 0 END)AS SPRD_STOCK_ESTMT_AMT
,SUM(CASE WHEN BIZ_TYPE = '4004' THEN SAL_AMT ELSE 0 END) AS CASH_DVD
,SUM(TAX_FEE) AS TAX_FEE
,SUM((BUY_AMT+SAL_AMT) * TB8.CMSN_ABTM) AS CMSN
,SUM(SAL_AMT-BUY_AMT) AS BRKV_AMT
,TB8.ABNO_INCM_CALC_BTCH AS ABNO_INCM_CALC_BTCH
FROM
(
    select * from $PARAM{'CMSSDB'}.MID_ABNO_INCM_CACL_DTL
    where ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
) tb1
inner join $PARAM{'CMSSDB'}.ABNO_INCM_CALC_LOG tb8
on tb1.ABNO_INCM_CALC_BTCH = tb8.ABNO_INCM_CALC_BTCH
inner join 
(
    select * from NsoVIEW.CSDC_INTG_SEC_ACCT
    where s_date <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
    and e_date > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
) tb2
on tb1.sec_acct = tb2.sec_acct
left outer join 
(
    select * from nspview.ACT_STK_INVST_CLSF_HIS
    where s_date <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
    and e_date > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
) tb3
on tb1.sec_acct = tb3.SEC_ACCT_NBR
inner join
(
--------- 期初、期末持有市值 ----------------------------------------------------
SELECT 
T1.SEC_CDE, 
T1.SEC_ACCT AS sec_acct,
t3.td_end_hold_vol * calc_s_prc as start_bal,
t4.td_end_hold_vol * calc_e_prc as end_bal
FROM
(
    SELECT
        SEC_CDE
        ,SEC_ACCT
        ,SUM(BUY_VOL - SAL_VOL) AS CHG_VOL
    FROM CMSSDATA.MID_ABNO_INCM_CACL_DTL
    WHERE ABNO_INCM_CALC_BTCH = '$PARAM{'abno_incm_calc_btch'}'
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
) tb4
on tb1.sec_acct = tb4.sec_acct
and tb1.sec_cde = tb4.sec_cde
left outer join
(
      ----高管名单（估算）--------------------------------------------------------------------  
         SELECT
            k2.OAP_ACCT_NBR
            ,CAST(SEC_CDE AS  CHAR(6)) AS SEC_CDE
            ,k2.MKT_SORT
        FROM
            NSoVIEW.CSDC_H_DSE_TRAD_LMT_CNDT k1
            INNER JOIN
            NsoVIEW.CSDC_INTG_SEC_ACCT k2
            ON k1.SHDR_ACCT = k2.SEC_ACCT AND k2.MKT_SORT = '0'
        WHERE
            k2.S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
            AND k2.E_DATE > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
        GROUP BY 1,2,3
        UNION ALL
        SELECT
            k2.OAP_ACCT_NBR
            ,k1.COMP_CDE AS SEC_CDE
            ,k2.MKT_SORT
        FROM
            (SELECT CERT_NBR,COMP_CDE FROM NsoVIEW.SZSE_LC_EXCUT_INFO 
             WHERE
                LENGTH(CERT_NBR)>=6
             GROUP BY 1,2
            ) k1
            INNER JOIN
            NsoVIEW.CSDC_INTG_SEC_ACCT k2
            ON k1.CERT_NBR = k2.CERT_NBR  AND k2.MKT_SORT = '1'
        WHERE
            k2.S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
            AND k2.E_DATE >  CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
           AND k2.MKT_SORT='1' AND k2.SEC_ACCT_SORT = '1'
        GROUP BY 1,2,3
) tb5
on tb1.sec_cde = tb5.sec_cde
and tb2.oap_acct_nbr = tb5.oap_acct_nbr
left outer join
(
     ----限售股股东（估算）--------------------------------------------------------------------  
    select shdr_acct, sec_cde
    from
    (
     SELECT 
         k1.SHDR_ACCT
        ,substr(CAST(1000000+k1.SEC_CDE AS CHAR(7)),2,6) as sec_cde
        ,k2.MKT_SORT
        -- ,CAST(k1.TRAD_DATE AS FORMAT 'yyyymmdd')                                AS RELEASE_DATE ---- 解禁日期
        -- ,CASE 
        --     WHEN k1.CAP_TYPE='XL' AND (k1.NEGT_TYPE = 'A' OR k1.NEGT_TYPE = 'B')    THEN 'SF'
        --     WHEN k1.CAP_TYPE='XL' AND  k1.NEGT_TYPE = 'F'                           THEN 'ZF'
        --     ELSE 'OTH'
        -- END AS CAP_TYPE        
        -- ,SUM(k1.TRANS_VOL)                                                      AS RELEASE_VOL  ---- 解禁数量
    FROM
        NsoVIEW.CSDC_H_SEC_TRAN k1
        INNER JOIN
        (SELECT SEC_CDE,MKT_SORT FROM NsoVIEW.CSDC_INTG_SEC_INFO
        WHERE
           S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
           AND E_DATE > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
           AND SEC_CTG = '11' AND MKT_LVL_SORT IN ('1','2','3')
           AND MKT_SORT = '0'
        )k2
        ON substr(CAST(1000000+k1.SEC_CDE AS CHAR(7)),2,6) = k2.SEC_CDE
    WHERE 
        k1.TRAD_DATE BETWEEN 
        (
            select max(calendar_date)
            from nsoview.tdsum_date_exchange 
            where calendar_date <= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') - interval '1' year
            and is_trd_dt = '1'
        )
        AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
        AND k1.TRAD_DIRC = 'S'
        AND k1.TRANS_TYPE = '00G'
        AND k1.CAP_TYPE  = 'XL' --AND k1.NEGT_TYPE ='F' 
        AND k1.EQUT_TYPE <> 'HL'  -- 实测未发现在此前限定条件有该取值，因此测试数据范围内，该条件是否限定不影响结果
        AND k1.TRANS_VOL <> 0
    GROUP BY 1,2,3
    UNION ALL
    SELECT 
         k1.SHDR_ACCT
        ,substr(CAST(1000000+k1.SEC_CDE AS CHAR(7)),2,6) as sec_cde
        ,k2.MKT_SORT
        -- ,CAST(k1.CHG_DATE AS FORMAT 'yyyymmdd')                                     AS RELEASE_DATE     ---- 中登记录的解禁日期
        -- ,CASE 
        --     WHEN  k1.STK_CHRC IN ('05','06')    THEN 'SF'
        --     WHEN  k1.STK_CHRC IN ('01','03')    THEN 'ZF'
        --     ELSE 'OTH'
        -- END AS CAP_TYPE
        -- ,SUM(ABS(k1.CHG_VOL))                                                       AS RELEASE_VOL  ---- 首发数量
    FROM
        NsoVIEW.CSDC_S_SHDR_HLD_CHG k1
        INNER JOIN
        (SELECT SEC_CDE,MKT_SORT FROM NsoVIEW.CSDC_INTG_SEC_INFO
        WHERE
           S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')  
           AND E_DATE > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
           AND SEC_CTG = '11' AND MKT_LVL_SORT IN ('1','2','3')
           AND MKT_SORT = '1'
        )k2
        ON substr(CAST(1000000+k1.SEC_CDE AS CHAR(7)),2,6) = k2.SEC_CDE
        INNER JOIN
        NsoVIEW.CSDC_S_SHDR_HLD_CHG k0
        ON k1.SHDR_ACCT = k0.SHDR_ACCT AND k1.SEC_CDE = k0.SEC_CDE AND k1.CHG_DATE = k0.CHG_DATE AND k1.SEAT_CDE = k0.SEAT_CDE
    WHERE 
        k1.CHG_DATE BETWEEN 
        (
            select max(calendar_date)
            from nsoview.tdsum_date_exchange 
            where calendar_date <= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') - interval '1' year
            and is_trd_dt = '1'
        ) AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
        
        AND k1.CHG_CDE  IN ('A50')
        AND k0.STK_CHRC IN ('00')       ---- 解禁后，股份性质为00，转为高管锁定股的不算
        
        AND k1.CHG_VOL < 0 AND k0.CHG_VOL >0 
        AND k1.CHG_VOL + k0.CHG_VOL = 0
        --  AND k1.BEF_CHG_HOLD_VOL > 0
    GROUP BY 1,2,3
    UNION ALL
    SELECT 
         k1.SHDR_ACCT
		,substr(CAST(1000000+k1.SEC_CDE AS CHAR(7)),2,6) as sec_cde
        ,k2.MKT_SORT
        -- ,CAST(k1.CHG_DATE AS FORMAT 'yyyymmdd')                                     AS RELEASE_DATE     ---- 中登记录的解禁日期
        -- ,CASE 
        --     WHEN  k1.STK_CHRC IN ('05','06')    THEN 'SF'
        --     WHEN  k1.STK_CHRC IN ('01','03')    THEN 'ZF'
        --     ELSE 'OTH'
        -- END AS CAP_TYPE
        -- ,SUM(ABS(k1.CHG_VOL))                                                       AS RELEASE_VOL  ---- 首发数量
    FROM
        NsoVIEW.CSDC_S_STK_CHG k1
        INNER JOIN
        (SELECT SEC_CDE,MKT_SORT FROM NsoVIEW.CSDC_INTG_SEC_INFO
        WHERE
           S_DATE <= CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
           AND E_DATE > CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD')
           AND SEC_CTG = '11' AND MKT_LVL_SORT IN ('1','2','3')
           AND MKT_SORT = '1'
        ) k2
        ON substr(CAST(1000000+k1.SEC_CDE AS CHAR(7)),2,6) = k2.SEC_CDE
        INNER JOIN
        NsoVIEW.CSDC_S_STK_CHG k0
        ON k1.SHDR_ACCT = k0.SHDR_ACCT AND k1.SEC_CDE = k0.SEC_CDE AND k1.CHG_DATE = k0.CHG_DATE AND k1.CSTD_UNIT = k0.CSTD_UNIT
    WHERE 
        k1.CHG_DATE BETWEEN 
        (
            select max(calendar_date)
            from nsoview.tdsum_date_exchange 
            where calendar_date <= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD') - interval '1' year
            and is_trd_dt = '1'
        )
        AND CAST('$PARAM{'e_date'}' AS DATE FORMAT 'YYYYMMDD') 
        
        AND k1.CHG_CDE  IN ('A50')
        AND k0.STK_CHRC IN ('00')       ---- 解禁后，股份性质为00，转为高管锁定股的不算
        
        AND k1.CHG_VOL < 0 AND k0.CHG_VOL >0 
        AND k1.CHG_VOL + k0.CHG_VOL = 0
        --  AND k1.BEF_CHG_HOLD_VOL > 0
    GROUP BY 1,2,3
    ) xsgd
    group by 1,2
) tb6
on tb1.sec_acct = tb6.shdr_acct
and tb1.sec_cde = tb6.sec_cde
left outer join
(
  ---- 十大股东 --------------------------------------------------------------------  
  SEL  
    T2.OAP_ACCT_NBR,
    T1.SEC_CDE,
    T1.MKT_SORT,
    SUM(TD_END_HOLD_VOL) as hold_vol,
    RANK() OVER( PARTITION BY t2.oap_acct_nbr, T1.SEC_CDE,T1.MKT_SORT ORDER BY SUM(TD_END_HOLD_VOL) DESC) AS RANK_1
  FROM 
    NSPVIEW.ACT_SEC_HOLD_HIS T1
    LEFT JOIN
    NSOVIEW.CSDC_INTG_SEC_ACCT T2 
    ON T1.SEC_ACCT_NBR = T2.SEC_ACCT
    AND T1.MKT_SORT = T2.MKT_SORT
    AND T2.S_DATE <= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD')
    AND T2.E_DATE > CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD')
  WHERE T1.S_DATE <= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD')
    AND T1.E_DATE >= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD')
    AND  T1.SEC_CDE IN
    (
        SELECT sec_cde
          FROM NSOVIEW.CSDC_INTG_SEC_INFO     
          where s_date <= CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD')
              AND e_date > CAST('$PARAM{'s_date'}' AS DATE FORMAT 'YYYYMMDD')
              AND sec_ctg ='11' --A股
              AND sec_reg_sts_sort NOT IN ('2','5')            --证券登记状态类别 2：退市、5：废弃
    )
    QUALIFY  RANK_1 <= 10
    GROUP BY 1,2,3
) tb7
on tb2.oap_acct_nbr = tb7.oap_acct_nbr
and tb1.sec_cde = tb7.sec_cde
group by 1,2,3,4,5,6,7,8,9,10,11,12,22
;


.IF ERRORCODE <> 0 THEN .QUIT 12;

.QUIT;

