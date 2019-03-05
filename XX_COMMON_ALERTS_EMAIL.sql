CREATE OR REPLACE PROCEDURE APPS.XX_COMMON_ALERTS_EMAIL (
   errbuf         OUT      VARCHAR2,
   retcode        OUT      VARCHAR2,
   p_alert_name   IN       VARCHAR2
)
/*****************************************************************************
     Procedure             : XX_COMMON_ALERTS_EMAIL
     Description          : This common procedure is called for sending the 
                            Alert email notification in HTML format and it 
                            can be used for any alert.
     Change List:
     ------------
     Name               Date        Version   Description
     --------------    -----------  -------   ------------------------------
     Venu Palakolanu   25-FEB-2019  1.0       Initial Version

******************************************************************************/
AS
   v_clob                  CLOB;
   v_list                  wf_mail.wf_recipient_list_t;
   v_email                 VARCHAR2 (300);
   i                       INTEGER    := 1;
   v_length                INTEGER    := 0;
   v_output                VARCHAR2 (2000);
   v_template              VARCHAR2 (2000);
   v_to_recipients         VARCHAR2 (2000);
   v_cc_recipients         VARCHAR2 (2000);
   v_bcc_recipients        VARCHAR2 (2000);
   v_subject               VARCHAR2 (2000);
   v_alert_id              alr_alerts.alert_id%TYPE;
   v_list_id               alr_actions.list_id%TYPE;
   v_list_application_id   alr_actions.list_application_id%TYPE;
   v_body                  alr_actions.BODY%TYPE;
   v_row_count             alr_action_set_checks.row_count%TYPE;
   v_check_id              alr_action_set_checks.alert_check_id%TYPE;
   v_alert_check_id        alr_action_set_checks.alert_check_id%TYPE;
   v_action_id             NUMBER;
   v_date_last_checked     DATE;
   v_last_update_date      DATE;
  
BEGIN
   fnd_file.put_line (fnd_file.LOG, '++---------------------Parameters----------------------++');
   fnd_file.put_line (fnd_file.LOG, ' : p_alert_name   : ' || p_alert_name);
   fnd_file.put_line (fnd_file.LOG, '++-----------------------------------------------------++');

   SELECT actions.to_recipients,
          actions.cc_recipients,
          actions.bcc_recipients,
          actions.subject,
          alr.alert_id,
          actions.list_id,
          actions.list_application_id,
          actions.body
     INTO v_to_recipients,
          v_cc_recipients,
          v_bcc_recipients,
          v_subject,
          v_alert_id,
          v_list_id,
          v_list_application_id,
          v_body
     FROM alr_alerts alr,
          alr_actions actions
    WHERE alr.alert_name = p_alert_name
      AND alr.alert_id = actions.alert_id
      AND actions.NAME = 'HTML Email'
      AND actions.enabled_flag = 'Y'
      AND actions.end_date_active IS NULL;

   IF v_list_id IS NOT NULL THEN
   
      SELECT to_recipients,
             cc_recipients,
             bcc_recipients
        INTO v_to_recipients,
             v_cc_recipients,
             v_bcc_recipients
        FROM alr_distribution_lists
       WHERE list_id = v_list_id
         AND application_id = v_list_application_id
         AND enabled_flag = 'Y'
         AND end_date_active IS NULL;
   END IF;

   i := 1;
   
   FOR rec IN (SELECT email_address,recipient_type FROM (SELECT REGEXP_SUBSTR (v_to_recipients, '[^,]+', 1, LEVEL) email_address, 'TO' recipient_type
                 FROM DUAL
                CONNECT BY REGEXP_SUBSTR (v_to_recipients, '[^,]+', 1, LEVEL) IS NOT NULL
               UNION              
                SELECT REGEXP_SUBSTR (v_cc_recipients, '[^,]+', 1, LEVEL) email_address,'CC' recipient_type
                FROM DUAL
                CONNECT BY REGEXP_SUBSTR (v_cc_recipients, '[^,]+', 1, LEVEL) IS NOT NULL
               UNION
                SELECT REGEXP_SUBSTR (v_bcc_recipients, '[^,]+', 1, LEVEL) email_address,'BCC' recipient_type
                FROM DUAL
                CONNECT BY REGEXP_SUBSTR (v_bcc_recipients, '[^,]+', 1, LEVEL) IS NOT NULL
                ORDER BY recipient_type DESC)
              WHERE email_address IS NOT NULL )
   LOOP
      fnd_file.put_line (1, 'Email added:' || rec.email_address ||' - ' || 'Recipient Type:' || rec.recipient_type);
      v_list (i).name := rec.email_address;
      v_list (i).address := rec.email_address;
      v_list (i).recipient_type := rec.recipient_type;
      i := i + 1;      
   END LOOP;
  
   --Fetching alert check ID and row counts
   SELECT row_count,
          check_id,
          alert_check_id
     INTO v_row_count,
          v_check_id,
          v_alert_check_id
     FROM alr_action_set_checks
    WHERE alert_id = v_alert_id
      AND alert_check_id = (SELECT MAX (alert_check_id)
                              FROM alr_action_set_checks
                             WHERE alert_id = v_alert_id);

   DBMS_LOB.createtemporary (v_clob, TRUE, DBMS_LOB.CALL);
   v_output := v_body || '<table border="1"><tr>';

   FOR rec IN (SELECT name, title
                   FROM alr_alert_outputs alo
                  WHERE alo.alert_id = v_alert_id
                    AND alo.enabled_flag = 'Y'
                    AND alo.end_date_active IS NULL
               ORDER BY alo.sequence)
   LOOP
      v_output := v_output || '<th>' || rec.title || '</th>';
   END LOOP;

   v_length := LENGTH (v_output);
   DBMS_LOB.WRITE (v_clob, v_length, 1, v_output);

   FOR rec IN (SELECT aloh.value,
                      alo.sequence
                   FROM alr_output_history aloh,
                        alr_alert_outputs alo
                  WHERE aloh.check_id = v_check_id
                    AND alo.alert_id = v_alert_id
                    AND aloh.name = alo.name
                    AND alo.enabled_flag = 'Y'
               ORDER BY aloh.row_number, alo.sequence)
   LOOP
      IF rec.sequence = 1 THEN
         v_output := '</tr><tr><td>' || rec.value || '</td>';

      ELSE
         v_output := '<td>' || rec.value || '</td>';

      END IF;

      DBMS_LOB.WRITE (v_clob, LENGTH (v_output), v_length + 1, v_output);
      v_length := v_length + LENGTH (v_output);
   END LOOP;

   v_output := '</tr></table><p>Best Regards, <br> Oracle Alert<p>';
   DBMS_LOB.WRITE (v_clob, LENGTH (v_output), v_length + 1, v_output);
   v_length := v_length + LENGTH (v_output);
   
   wf_mail.send (p_subject             => v_subject,
                 p_message             => v_clob,
                 p_recipient_list      => v_list,
                 p_content_type        => 'text/html',
                 p_module              => 'WF'
                );
                
   fnd_file.put_line (1, 'email sent');
   RETURN;
EXCEPTION
   WHEN NO_DATA_FOUND
   THEN
      fnd_file.put_line (1,'Not found check_id in alr_action_history for alert=' || p_alert_name );
      fnd_file.put_line (1,'Check if Alert has "Keep x Days" (maintain_history_days) attribute setup!');
      RAISE;
   WHEN OTHERS
   THEN
      fnd_file.put_line (1, 'Exception in when OTHERS for procedure xxbr_common_alerts_email');
      RAISE;
END;
/
