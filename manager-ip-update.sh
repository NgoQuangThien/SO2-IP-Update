#!/bin/bash

. /usr/sbin/so-common

is_manager_node() {
	# Check to see if this is a manager node
	role=$(lookup_role)
	[ $role == 'manager' ] && return 0
	return 1
}

is_sensor_node() {
	# Check to see if this is a sensor (forward) node
	role=$(lookup_role)
	[ $role == 'sensor' ] && return 0
	return 1
}

is_search_node() {
	# Check to see if this is a search node
	role=$(lookup_role)
	is_single_node_grid && return 0
	[ $role == 'searchnode' ] && return 0
	return 1
}

change_ip_on_manager() {
	#	Lấy IP manager cũ
	if [ -z "$OLD_IP" ]; then
		OLD_IP=$(lookup_pillar "managerip")
	
		# Nếu $OLD_IP rỗng
		if [ -z "$OLD_IP" ]; then
			fail "Unable to find old IP; possible salt system failure"
		fi

		echo "Found old IP $OLD_IP."
	fi

	#	Lấy IP mới từ interface
	if [ -z "$NEW_IP" ]; then
		iface=$(lookup_pillar "mainint" "host")
		NEW_IP=$(ip -4 addr list $iface | grep inet | cut -d' ' -f6 | cut -d/ -f1)

		#	Nếu $NEW_IP rỗng
		if [ -z "$NEW_IP" ]; then
			fail "Unable to detect new IP on interface $iface."
		fi

		echo "Detected new IP $NEW_IP on interface $iface."
	fi

	#	Thoát nếu IP không thay đổi
	if [ "$OLD_IP" == "$NEW_IP" ]; then
		fail "IP address has not changed"
	fi

	echo "About to change old IP $OLD_IP to new IP $NEW_IP."

	echo ""
	read -n 1 -p "Would you like to continue? (y/N) " CONTINUE
	echo ""

	#	Đồng ý thay đổi IP
	if [ "$CONTINUE" == "y" ]; then
		#	Duyệt các file chứa $OLD_IP trong thư mục "/opt/so/saltstack" và "/etc"
		#	-r - tìm kiến tất cả các file con trong thư 
		#	-i - tìm kiếm chính xác từ khóa không phân biệt hoa với thường
		#	-l - chỉ hiện thị tên file chứa từ khóa
		for file in $(grep -rlI $OLD_IP /opt/so/saltstack /etc); do
			echo "Updating file: $file"
			#	Thay $OLD_IP bằng $NEW_IP
			sed -i "s|$OLD_IP|$NEW_IP|g" $file
		done

		#	Thay đổi IP cho user root trong MySQL
		echo "Granting MySQL root user permissions on $NEW_IP"
		docker exec -i so-mysql mysql --user=root --password=$(lookup_pillar_secret 'mysql') -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'$NEW_IP' IDENTIFIED BY '$(lookup_pillar_secret 'mysql')' WITH GRANT OPTION;" &> /dev/null
		echo "Removing MySQL root user from $OLD_IP"
		docker exec -i so-mysql mysql --user=root --password=$(lookup_pillar_secret 'mysql') -e "DROP USER 'root'@'$OLD_IP';" &> /dev/null

		echo "The IP has been changed from $OLD_IP to $NEW_IP."

		echo
		read -n 1 -p "The system must reboot to ensure all services have restarted with the new configuration. Reboot now? (y/N)" CONTINUE
		echo

		#	Khởi động lại thiết bị
		if [ "$CONTINUE" == "y" ]; then
			reboot
		fi
	else
		echo "Exiting without changes."
	fi
}

change_ip_on_other_role() {
	echo "About to change MANAGER IP."

	echo ""
	read -n 1 -p "Would you like to continue? (y/N) " CONTINUE
	echo ""

	if [ "$CONTINUE" == "y" ]; then
		read -p "Enter old manager ip: " OLD_IP
		#	Thoát nếu IP không hợp lệ
		if ! valid_ip4 "$OLD_IP"; then
			fail "Invalid IP"
		fi

		read -p "Enter new manager ip: " NEW_IP
		#	Thoát nếu IP không hợp lệ
		if ! valid_ip4 "$NEW_IP"; then
			fail "Invalid IP"
		fi

		#	IP không thay đổi
		if [ "$OLD_IP" == "$NEW_IP" ]; then
			fail "IP address has not changed"
		fi

		#	Tìm kiếm file chứa MANAGER IP cũ trong "/ect"
		if [ -z "$(grep -rlI $OLD_IP /etc)" ]; then
			fail "The old IP MANAGER can't be found"
		fi

		#	Thực hiện ghi đè IP mới
		for file in $(grep -rlI $OLD_IP /opt/so/saltstack /etc); do
			echo "Updating file: $file"
			#	Thay $OLD_IP bằng $NEW_IP
			sed -i "s|$OLD_IP|$NEW_IP|g" $file
		done

		echo "The IP has been changed from $OLD_IP to $NEW_IP."

		echo ""
		read -n 1 -p "The system must reboot to ensure all services have restarted with the new configuration. Reboot now? (y/N)" CONTINUE
		echo ""

		#	Khởi động lại thiết bị
		if [ "$CONTINUE" == "y" ]; then
			reboot
		fi
	else
		echo "Exiting without changes."
	fi
}

main() {
	read -n 1 -p "This is manager? (y/N) " ROLE
	echo ""

	if [ "$ROLE" == "y" ]; then
		if is_manager_node; then
			change_ip_on_manager
		else
			fail "CAN YOU READ THE TEXT ABOVE?"
		fi
	else
		change_ip_on_other_role
	fi
}

main