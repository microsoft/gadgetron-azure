FROM python:3-buster

RUN pip install pyinotify prometheus_client
COPY log-monitor.py ./

EXPOSE 8080
CMD ["sh", "-c", "python log-monitor.py -l ${GADGETRON_LOG_FILE}" ]