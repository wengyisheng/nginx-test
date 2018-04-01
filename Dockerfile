FROM nginx:latest
COPY ./index.html /usr/share/nginx/html/index.html 
EXPOSE 80
STOPSIGNAL SIGTERM
CMD ["nginx", "-g", "daemon off;"]
