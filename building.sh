#!/bin/bash

# Biến cấu hình
PORT="443"
CONTAINER_NAME="mtproto-proxy"
VOLUME_NAME="proxy-config"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

generate_secret() {
  openssl rand -hex 16
}

SECRET=$(generate_secret)
if [ -z "$SECRET" ]; then
  echo -e "${RED}Lỗi: Không thể tạo secret.${NC}"
  exit 1
fi

VPS_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 https://ipv4.icanhazip.com)
if [ -z "$VPS_IP" ]; then
  echo -e "${RED}Lỗi: Không thể lấy IP công cộng IPv4. Đặt thủ công: VPS_IP='your_vps_ip' ./build_mtproto.sh${NC}"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Vui lòng chạy script với quyền root (sudo).${NC}"
  exit 1
fi

echo -e "${YELLOW}Cài đặt curl và wget nếu chưa có...${NC}"
apt-get update -y
apt-get install -y curl wget

# Cài đặt Docker
if ! command -v docker &> /dev/null; then
  echo -e "${YELLOW}Cài đặt Docker...${NC}"
  curl -fsSL https://get.docker.com | sh
  systemctl start docker
  systemctl enable docker
  usermod -aG docker $USER
else
  echo -e "${GREEN}Docker đã được cài đặt.${NC}"
fi

if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo -e "${YELLOW}Dừng và xóa container cũ...${NC}"
  docker stop $CONTAINER_NAME
  docker rm $CONTAINER_NAME
fi

if docker volume ls -q | grep -q "$VOLUME_NAME"; then
  echo -e "${YELLOW}Xóa volume cũ...${NC}"
  docker volume rm $VOLUME_NAME
fi

# Tối ưu hóa tài nguyên: Giới hạn RAM và CPU cho container
echo -e "${YELLOW}Chạy MTProto Proxy với secret mới...${NC}"
docker run -d -p $PORT:$PORT --name=$CONTAINER_NAME --restart=always \
  --memory="512m" --cpus="0.5" \
  -v $VOLUME_NAME:/data \
  -e SECRET=$SECRET \
  -e WORKERS=1 \
  telegrammessenger/proxy:latest

if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo -e "${GREEN}MTProto Proxy đang chạy.${NC}"
else
  echo -e "${RED}Lỗi: Không thể khởi động proxy. Xem log:${NC}"
  docker logs $CONTAINER_NAME
  exit 1
fi

if command -v ufw &> /dev/null; then
  echo -e "${YELLOW}Mở cổng $PORT trên tường lửa...${NC}"
  ufw allow $PORT/tcp
elif command -v firewall-cmd &> /dev/null; then
  echo -e "${YELLOW}Mở cổng $PORT trên firewalld...${NC}"
  firewall-cmd --permanent --add-port=$PORT/tcp
  firewall-cmd --reload
fi

CONTAINER_STATUS=$(docker ps -f name=$CONTAINER_NAME --format "{{.Status}}")
CONTAINER_ID=$(docker ps -q -f name=$CONTAINER_NAME)

echo -e "\n${GREEN}=== Thông tin MTProto Proxy ===${NC}"
echo -e "IP VPS (IPv4): ${YELLOW}$VPS_IP${NC}"
echo -e "Port: ${YELLOW}$PORT${NC}"
echo -e "Secret: ${YELLOW}$SECRET${NC}"
echo -e "Container Name: ${YELLOW}$CONTAINER_NAME${NC}"
echo -e "Container ID: ${YELLOW}$CONTAINER_ID${NC}"
echo -e "Container Status: ${YELLOW}$CONTAINER_STATUS${NC}"
echo -e "\nLink proxy:"
echo -e "${YELLOW}tg://proxy?server=$VPS_IP&port=$PORT&secret=$SECRET${NC}"
echo -e "${YELLOW}https://t.me/proxy?server=$VPS_IP&port=$PORT&secret=$SECRET${NC}"
echo -e "Link chống DPI:"
echo -e "${YELLOW}tg://proxy?server=$VPS_IP&port=$PORT&secret=dd$SECRET${NC}"
echo -e "\n${GREEN}Hoàn tất! Copy thông tin phía trên để sử dụng.${NC}"
echo -e "Để kiểm tra log: ${YELLOW}docker logs $CONTAINER_NAME${NC}"
echo -e "Để dừng proxy: ${YELLOW}docker stop $CONTAINER_NAME${NC}"

echo -e "${YELLOW}Lưu thông tin vào mtproto_info.txt...${NC}"
cat << EOF > mtproto_info.txt
=== Thông tin MTProto Proxy ===
IP VPS (IPv4): $VPS_IP
Port: $PORT
Secret: $SECRET
Container Name: $CONTAINER_NAME
Container ID: $CONTAINER_ID
Container Status: $CONTAINER_STATUS



Kết nối thông qua : tg://proxy?server=$VPS_IP&port=$PORT&secret=$SECRET
Hoặc : https://t.me/proxy?server=$VPS_IP&port=$PORT&secret=$SECRET
Link chống DPI: tg://proxy?server=$VPS_IP&port=$PORT&secret=dd$SECRET

Kiểm tra log: docker logs $CONTAINER_NAME
Dừng proxy: docker stop $CONTAINER_NAME
EOF
echo -e "${GREEN}Thông tin đã được lưu vào mtproto_info.txt${NC}"
