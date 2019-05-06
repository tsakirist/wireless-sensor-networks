import re

# Sets data as global, so that functions can access it even when the script is imported(just call set_data())
def set_global(content_string, content_lines):
	global data, lines
	data = content_string
	lines = content_lines

# Gets the name of the topology and also the seconds the simulation has run
def get_info():
	topology_name = lines[0][lines[0].find(":")+2:]
	secs = lines[1][lines[1].find(":")+2:]
	return [topology_name, secs]

# Returns the file contents in a string and in a list[1st_line, 2nd_line, ... , nth_line]
def read_file(name):
	with open(name, "r") as f:
		data = f.read()
		f.seek(0,0)
		lines = [x.strip("\n") for x in f.readlines()]
	return [data, lines]

# Returns the total broadcasted packets of the node
def get_node_bcast(node):
	pat = "Node " + str(node) + " broadcast"
	bcast = data.count(pat)
	return bcast

# Returns the total transmitted packets of the node (either broadcast or forward)
def get_node_trans(node):
	pat = "Node " + str(node) + " forward"
	bcast = get_node_bcast(node)
	fwd = data.count(pat)
	total = bcast + fwd
	return total

# Returns the total transmitted packets of the network
def get_total_trans():
	pat1 = "broadcast"
	pat2 = "forward"
	bcast = data.count(pat1)
	fwd = data.count(pat2)
	total = bcast + fwd
	return total

# Returns the number of nodes received a specific message
def get_coverage(node_id, seq_no):
	pat =  "Saved packet nodeId: " + str(node_id) + " seqNo: " + str(seq_no) + " @"
	total = data.count(pat)
	return total

# Returns the number of packets a node has dropped
def get_node_dropped_pkts(node_id):
	pat = "Node " + str(node_id) + " packet dropped"
	total = data.count(pat)
	return total

# Returns the total number of dropped packets of the network
def get_total_dropped_pkts():
	pat = "packet dropped"
	total = data.count(pat)
	return total

# Returns the total number of nodes
def get_num_nodes():
	indx = data.rfind('Booted')
	temp = data[:indx]
	num_nodes = temp[temp.rfind("(")+1:temp.rfind(")")]
	return int(num_nodes)

# Converts h:mm:ss to milliseconds
def convert_to_ms(h, m, s):
	return (h*3600 + 60*m + s)*1000

# Returns nodes dictionary which contains the packet latencies for every node
def get_latencies():
	bcast_pat = ".*?(\d+)\sbroadcasting\s(\d+).*?(\d+):(\d+):(\d+\.\d+)"
	saved_pat = "Saved.*?(\d+).*?(\d+).*?(\d):(\d+):(\d+\.\d+)"
	matcher1 = re.compile(bcast_pat)
	matcher2 = re.compile(saved_pat)
	num = get_num_nodes()
	nodes = {}
	start_times = {}
	# Initialize nodes dictionary
	for i in range(num+1):
		if get_node_bcast(i):
			nodes[i] = {}
	for line in lines:
		match1 = matcher1.search(line)
		match2 = matcher2.search(line)
		if match1:
			seq = {}
			node_id = int(match1.group(1))
			seq_no = int(match1.group(2))
			h = int(match1.group(3))
			m = int(match1.group(4))
			s = float(match1.group(5))
			start_time = convert_to_ms(h, m, s)
			start_times[node_id] = start_time
			nodes[node_id][seq_no] = []
		if match2:
			node_id = int(match2.group(1))
			seq_no  = int(match2.group(2))
			h = int(match2.group(3))
			m = int(match2.group(4))
			s = float(match2.group(5))
			end_time = convert_to_ms(h, m, s)
			for node in nodes.keys():
				if node == node_id:
					for seq in nodes[node]:
						if seq == seq_no:
							dt = end_time - start_times[node_id]
							dt = round(dt, 6)
							nodes[node][seq].append(dt)
	return nodes

# Outputs the statistics of the simulation in TOSSIM
def main():
	global data, lines

	node_trans = {}
	num_bcast = raw_input("Enter a suffix for file output name: ")
	name = "out.txt"
	data, lines = read_file(name)
	topology_name, secs = get_info()
	num_nodes = get_num_nodes()
	nodes_latencies = get_latencies()

	with open("statistics/" + topology_name + "_" + num_bcast + ".txt", "w") as f:
		f.write("* Topology: " + topology_name + "\n* Simulation has run for " + secs + " simulated seconds\n\n\n")
		f.write("i)The actual per-node transmissions:\n\n")
		for i in range(num_nodes + 1):
			num_trans = get_node_trans(i)
			node_trans[i] = num_trans
			temp = "Node " + str(i) + "\ttransmitted " + str(num_trans) + "\tpackets" + "\n"
			f.write(temp)

		total = sum(node_trans.values())
		temp = "Total transmissions: " + str(total) + "\n"
		f.write("\n\nii)The total number of transmissions:\n\n")
		f.write(temp)

		f.write("\n\niii)The average per-node transmissions(%):\n\n")
		for i in node_trans.keys():
			temp = "Node " + str(i) + "\tpercentage: " + str(round(float(node_trans[i])/total, 3) * 100) + "%\n"
			f.write(temp)

		f.write("\n\niv)The coverage (number of nodes that received a given message):\n\n")
		mylist = []
		for i in node_trans.keys():
			cov_list = []
			bcast = get_node_bcast(i)
			if(bcast):
				f.write("Node " + str(i) + ":\nPacket seq --> #nodes\n\t")
				for j in range(bcast):
					if not j%5:
						f.write("\n\t")
					cov = round((get_coverage(i, j) / float(num_nodes)), 3) * 100
					cov_list.append(cov)
					# temp = str(j) + "\t-->\t" + str(get_coverage(i, j)) + "\t|\t"
					temp = str(j) + "\t-->\t" + str(get_coverage(i, j)) + "\t" + str(cov) + "%\t|\t"
					f.write(temp)
				t = round(sum(cov_list) / float(bcast), 2)
				f.write("\n\tAverage node coverage: " + str(t) + "%")
				f.write("\n\n")

		#TODO convert the below monster to functions
		node_dict = {}
		sys_dict = {0:[], 1:[], 2:[]}
		f.write("\nv)Minimum, average, maximum message latency(ms):\n\n")
		for i in nodes_latencies.keys():
			node_dict[i] =  {0:[], 1:[], 2:[]}
			# Compute min, avg, max latency for every node's packet
			f.write("Node " + str(i) + ":\nPacket \t-->   min,\t\t   avg,\t\t   max\n")
			for seq in nodes_latencies[i].keys():
				dt_list = nodes_latencies[i][seq]
				if len(dt_list) == 0:
					temp = "\t" + str(seq) + "\t-->\tPacket didn't get received by anyone\n\n"
					f.write(temp)
					continue
				t_min = min(dt_list)
				t_avg = round(sum(dt_list) / float(len(dt_list)), 6)
				t_max = max(dt_list)
				node_dict[i][0].append(t_min)
				node_dict[i][1].append(t_avg)
				node_dict[i][2].append(t_max)
				temp = "\t" + str(seq) + "\t-->\t" + str(t_min) + ",\t"
				# Add a tab when number has less than 6 digits, for pretty-output
				if len(str(t_min)) < 7:
					temp += "\t"
				temp += str(t_avg) + ",\t" + str(t_max) + "\n\n"
				f.write(temp)
			# Compute total min, avg, max latency for every node
			t_min_list = node_dict[i][0]
			t_avg_list = node_dict[i][1]
			t_max_list = node_dict[i][2]
			t_min = min(t_min_list)
			t_avg = round(sum(t_avg_list) / float(len(t_avg_list)), 6)
			t_max = max(t_max_list)
			sys_dict[0].append(t_min)
			sys_dict[1].append(t_avg)
			sys_dict[2].append(t_max)
			temp = "Total \t--> " + str(t_min) + ",\t" + str(t_avg) + ",\t" + str(t_max)
			f.write(temp)
			f.write("\n\n")
		# Compute system total min, avg, max latency
		sys_min = min(sys_dict[0])
		sys_avg = round(sum(sys_dict[1]) / float(len(sys_dict[1])), 6)
		sys_max = max(sys_dict[2])
		temp = "System Total:\n\tmin: " + str(sys_min) + "\n\tavg: " + str(sys_avg) + "\n\tmax: " + str(sys_max)
		f.write(temp)
		f.write("\n\n")

		f.write("\nvi)The actual per-node dropped packets:\n\n")
		for i in node_trans.keys():
			temp = "Node " + str(i) + "\thas " + str(get_node_dropped_pkts(i)) + "\tdropped packets\n"
			f.write(temp)

		f.write("\n\nvii)The total number of dropped packets:\n\n")
		total = get_total_dropped_pkts()
		temp = "Total dropped packets: " + str(total)
		f.write(temp)

if __name__ == '__main__':
	main()
