FROM node:20-alpine

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install --omit=dev

COPY src ./src

RUN mkdir -p /usr/src/app/logs

EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD node -e "const http=require('http');const body=JSON.stringify({query:'query Health { health }'});const req=http.request({hostname:'127.0.0.1',port:process.env.PORT||4000,path:'/',method:'POST',headers:{'content-type':'application/json','content-length':Buffer.byteLength(body)}},res=>{let data='';res.on('data',chunk=>data+=chunk);res.on('end',()=>{process.exit(res.statusCode===200 && data.includes('ok') ? 0 : 1);});});req.on('error',()=>process.exit(1));req.write(body);req.end();"
CMD ["npm", "start"]
