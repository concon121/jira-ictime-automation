#!/bin/bash

# Enable for debugging
#set -x

# =============================================================================
# Input Params
# =============================================================================

USER_NAME="$1"
PASSWORD="$2"

LAST_CASE=""
SEARCH_OUTPUT_FILE="activity.json"
WORKLOG_OUTPUT_FILE="worklogger.json"
FORM_TEMPLATE="form_data.template"

TIMESHEET_KEY="TIME-22"

ALREADY_LOGGED="already_logged"
LOGGED_WORK="log_work"
NOT_WORKED="not_worked"

# =============================================================================
# cURL Headers
# =============================================================================

CONTENT_TYPE_FORM="Content-Type:application/x-www-form-urlencoded; charset=UTF-8"
CONTENT_TYPE_JSON="Content-Type:application/json"
NO_ATL="X-Atlassian-Token: no-check"
NO_CACHE="Cache-Control: no-cache"

# =============================================================================
# JIRA Endpoints
# =============================================================================

JIRA_BASE_URL="https://<url>"
REST="/rest/api/2"

SEARCH="/search?jql=<query>&fields=key"
IC_TIME="/secure/IctCreateWorklog.jspa"
ISSUE="/issue/"
WORKLOG="/worklog"

# =============================================================================
# JQL
# =============================================================================

AND="+AND+"
PROJECTS='project+IN+("<projects>")'
ABOUT_ME="text~${USER_NAME}"
UPDATED_TODAY="updatedDate>=startOfDay()"
UPDATED_BETWEEN="updatedDate>=-<start>d+AND+updatedDate<=-<end>d"


# =============================================================================
# Funcions
# =============================================================================

function getJql() {

  local day="$1"

  if [[ "${day}" -eq 1 ]]
  then
    jql="${ABOUT_ME}${AND}${UPDATED_TODAY}${AND}${PROJECTS}"
  else
    start=${day}
    end=`expr ${day} - 1`

    jql="${ABOUT_ME}${AND}${UPDATED_BETWEEN}${AND}${PROJECTS}"
    jql=`echo "$jql" | sed "s|<start>|${start}|g"`
    jql=`echo "$jql" | sed "s|<end>|${end}|g"`
  fi 

}

function getSearchEndpoint() {
  
  local jql="$1"
  search=`echo "${JIRA_BASE_URL}${REST}${SEARCH}" | sed "s|<query>|${jql}|g"`

}

function buildComment() {

  local file="$1"
  local day="$2"
  comments=(`jq -r '.issues[].key' "${file}"`)
  comment=`echo ${comments[@]}`

  hasCase=`echo "${comment}" | grep "CASE"`

  WEEKEND="(Sat|Sun)"

  if [[ -z "${hasCase}" ]] && [[ -z `date -d "\`date\` -\`expr ${day} - 1\` days" | grep "${WEEKEND}"` ]]
  then
    comment+=" ${LAST_CASE}"
  else 
    LAST_CASE="${comment}"
  fi

}

function get() {

  local endpoint="$1"  
  local output="$2"
  
  echo "Calling endpoint: ${endpoint}"
  curl -s -u "${USER_NAME}:${PASSWORD}" -o "${output}" -H "${NO_CACHE}" "${endpoint}" > /dev/null 

  if [[ $? -ne 0 ]]
  then
    echo "Request Failed!"
  fi
 # sleep 5

}


function getWorkLog() {

  get "${JIRA_BASE_URL}${REST}${ISSUE}${TIMESHEET_KEY}${WORKLOG}" "${WORKLOG_OUTPUT_FILE}"

}

function submitWorklog() {

  local dataFile="$1"
  echo "Calling endpoint: ${JIRA_BASE_URL}${IC_TIME}"
  echo "Submitting work in file: $dataFile"
  cat "$dataFile"
  #curl -X POST --data-urlencode "@${dataFile}" "https://httpbin.org/post" -H "${NO_CACHE}" -H "${CONTENT_TYPE_FORM}" --trace-ascii /dev/stdout  > ${dataFile}.out

  curl -u "${USER_NAME}:${PASSWORD}" -X POST --data-urlencode "@${dataFile}" "${JIRA_BASE_URL}${IC_TIME}" -H "${NO_CACHE}" -H "${CONTENT_TYPE_FORM}" --trace-ascii /dev/stdout  > ${dataFile}.out

  if [[ $? -ne 0 ]]
  then
    echo "Request Failed!"
  fi


}

# =============================================================================
# Main
# =============================================================================


getWorkLog

# Go back 7 days
for day in `seq 1 7`
do

  processingDate=`date -d "\`date\` -\`expr ${day} - 1\` days" +"%F"`  
  processingDateLong=`date -d "\`date\` -\`expr ${day} - 1\` days"`

  if [[ "${dates[@]}" == *$processingDate* ]]
  then
    echo "${processingDateLong}" >> "${ALREADY_LOGGED}"
  else

    dates=(`jq -r ".worklogs[] | select(.author.name == \"${USER_NAME}\") | .started" "${WORKLOG_OUTPUT_FILE}"`)

    getJql "${day}"
    getSearchEndpoint "${jql}"

    get "${search}" "${SEARCH_OUTPUT_FILE}"
    buildComment "${SEARCH_OUTPUT_FILE}" "${day}"

    # If there was some work done
    if [[ ! -z `echo "${comment}" | sed "s/ //g"` ]]
    then
      started=`date -d "${processingDate}" "+%d/%b/%y %R %p"`
      cat "${FORM_TEMPLATE}" | sed "s/<comment>/${comment}/g" | sed "s|<started>|${started}|g" > "${processingDate}.form"
      submitWorklog "${processingDate}.form"     
      echo "${processingDateLong} : ${comment}" >> "${LOGGED_WORK}" 
      #sleep 2
    else
      echo "${processingDateLong}" >> "${NOT_WORKED}"
    fi
  
  fi
done


# =============================================================================
# Log what you did
# =============================================================================

echo "Logged work: "
cat "${LOGGED_WORK}"

echo ""

echo "No work logged for:"
cat "${NOT_WORKED}"

echo ""

echo "You have already logged work for:"
cat "${ALREADY_LOGGED}"

# =============================================================================
# Clean up after yourself!
# =============================================================================

rm -f activity
rm -f data
rm -f "${LOGGED_WORK}"
rm -f "${NOT_WORKED}"
rm -f "${ALREADY_LOGGED}"
rm -f "${SEARCH_OUTPUT_FILE}"
#rm -f "${WORKLOG_OUTPUT_FILE}"


