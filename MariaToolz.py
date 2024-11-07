import os
import re
import ssl
import urllib2
import json
import Tkinter as tk
import threading
import random
from collections import OrderedDict

# Global variables
constants = OrderedDict()
h6_changes = {}  # 6-hr price change
total_supplies = {}
royalty_tokens = []

PULSECAN_API_BASE_URL = "https://api.scan.pulsechain.com/api/v2"
DEXSCREENER_API_BASE_URL = "https://api.dexscreener.io/latest/dex/tokens"

run_count = 0

class Tooltip:
    def __init__(self, widget):
        self.widget = widget
        self.tip_window = None
        self.tip_label = None

    def show_tip(self, tip_text, x, y):
        if not self.tip_window:
            self.tip_window = tw = tk.Toplevel(self.widget)
            tw.wm_overrideredirect(True)
            tw.wm_geometry("+{}+{}".format(x, y))
            self.tip_label = tk.Label(tw, text=tip_text, justify=tk.LEFT,
                                      background="lightyellow", relief=tk.SOLID, borderwidth=1,
                                      font=("tahoma", "8", "normal"))
            self.tip_label.pack(ipadx=1)
        else:
            self.update_tip(tip_text, x, y)

    def update_tip(self, tip_text, x, y):
        if self.tip_window:
            self.tip_window.wm_geometry("+{}+{}".format(x, y))
            self.tip_label.config(text=tip_text)

    def hide_tip(self):
        if self.tip_window:
            self.tip_window.destroy()
            self.tip_window = None
            self.tip_label = None

def generate_base_color():
    # Generate a random but not too dark base color
    return "#{:02x}{:02x}{:02x}".format(
        random.randint(130, 204),
        random.randint(130, 204),
        random.randint(130, 204)
    )

def generate_shade_of_color(base_color, factor=1.2):

    r = int(base_color[1:3], 16)
    g = int(base_color[3:5], 16)
    b = int(base_color[5:7], 16)
    
    # Lighten by the given factor
    r = max(0, min(255, int(r * factor)))  
    g = max(0, min(255, int(g * factor)))
    b = max(0, min(255, int(b * factor)))
    
    return "#{:02x}{:02x}{:02x}".format(r, g, b)

def create_dynamic_tooltip(widget, get_text_callback):
    tooltip = Tooltip(widget)

    def on_enter(event):
        update_tooltip(event)

    def on_motion(event):
        update_tooltip(event)

    def on_leave(event):
        tooltip.hide_tip()

    def update_tooltip(event):
        idx = widget.nearest(event.y)
        tooltip_text = get_text_callback(idx)
        tooltip.show_tip(tooltip_text, event.x_root + 20, event.y_root + 20)

    widget.bind('<Enter>', on_enter)
    widget.bind('<Motion>', on_motion)
    widget.bind('<Leave>', on_leave)

def extract_constants_from_file(file_path):
    constants = OrderedDict()
    royalty_tokens = OrderedDict()
    all_tokens = OrderedDict()
    try:
        with open(file_path, 'r') as file:
            content = file.read()
            
            # Extract all tokens
            all_matches = re.findall(r'address(?: constant)? (\w+)? ?= ?address\((0x[a-fA-F0-9]{40})\);', content)
            for name, address in all_matches:
                if name:
                    all_tokens[name.strip()] = address.strip()
                else:
                    all_tokens[address.strip()] = address.strip()

            # Identify royalty tokens
            royalty_section = re.search(r'// royalty tokens\s*/\*(.*?)\*/', content, re.DOTALL)
            if royalty_section:
                royalty_addresses = re.findall(r'(0x[a-fA-F0-9]{40})', royalty_section.group(1))
                for address in royalty_addresses:
                    royalty_tokens[address.strip()] = address.strip()

            # Separate constants and royalty tokens while maintaining order
            for name, address in all_tokens.items():
                if address in royalty_tokens:
                    royalty_tokens[address] = name
                else:
                    constants[name] = address

    except Exception as e:
        print("Failed to extract tokens from file: {}".format(e))
    
    print("Extracted {} constants and {} royalty tokens".format(len(constants), len(royalty_tokens)))
    return constants, royalty_tokens

def get_token_scan(address):
    token_info = {}
    search_api_url = "{}/search?q={}".format(PULSECAN_API_BASE_URL, address)
    
    try:
        search_response = simple_get(search_api_url)
        if search_response['status_code'] == 200:
            search_data = json.loads(search_response['content'])
            if 'items' in search_data and search_data['items']:
                item = search_data['items'][0]
                token_info['name'] = item.get('name', 'Token Info Not Available')
                token_info['symbol'] = item.get('symbol', '')
    
        token_api_url = "{}/tokens/{}".format(PULSECAN_API_BASE_URL, address)
        token_response = simple_get(token_api_url)
        if token_response['status_code'] == 200:
            token_data = json.loads(token_response['content'])
            if token_data:
                total_supply = token_data.get('total_supply', '0')
                decimals = int(token_data.get('decimals', 18))
                if total_supply:
                    formatted_supply = "{:,.2f}".format(float(total_supply) / (10 ** decimals))
                    total_supplies[address] = formatted_supply
                token_info['total_supply'] = total_supply
                token_info['decimals'] = decimals
    except Exception as e:
        print("Failed to retrieve info for {}: {}".format(address, e))
        total_supplies[address] = "N/A"
    
    return token_info
def get_token_dex(address):
    token_dex = {}
    api_url = "{}/{}".format(DEXSCREENER_API_BASE_URL, address)
    print("Calling DexScreener API:", api_url)
    try:
        response = simple_get(api_url)
        print("Raw response:", response['content'])
        if response['status_code'] == 200:
            data = json.loads(response['content'])
            print("Parsed data:", json.dumps(data, indent=2))
            if 'pairs' in data and data['pairs']:
                pair_data = data['pairs'][0]
                token_dex['priceUsd'] = float(pair_data.get('priceUsd', '0').replace(',', ''))
                token_dex['volume_h24'] = float(pair_data.get('volume', {}).get('h24', '0'))
                token_dex['fdv'] = float(pair_data.get('fdv', '0'))
                token_dex['h6_price_change'] = float(pair_data.get('priceChange', {}).get('h6', '0'))
                token_dex['baseToken'] = pair_data.get('baseToken', {})
                print("Extracted token_dex data:", token_dex)
            else:
                print("No pairs data found in response")
        else:
            print("Failed API call, status:", response['status_code'])
    except Exception as e:
        print("Exception processing DexScreener data:", str(e))
    return token_dex

def update_color_and_tooltip(idx, color, h6_price_change):
    price_list.itemconfig(idx, {'fg': color})
    h6_changes[idx] = h6_price_change
    print("Updated color to {} and h6_change to {} for index {}".format(color, h6_price_change, idx))
    root.update_idletasks()  # Force GUI update

def update_fdv_mktcap_colors():
    for idx in range(fdv_list.size()):
        fdv_value = fdv_list.get(idx).replace("$", "").replace(",", "")
        mktcap_value = mktcap_list.get(idx).replace("$", "").replace(",", "")
        
        try:
            fdv = float(fdv_value) if fdv_value != "N/A" else float('inf')
            mktcap = float(mktcap_value) if mktcap_value != "N/A" else float('inf')
            
            if fdv < mktcap:
                fdv_list.itemconfig(idx, {'fg': 'grey'})
                mktcap_list.itemconfig(idx, {'fg': 'black'})
            elif mktcap < fdv:
                mktcap_list.itemconfig(idx, {'fg': 'grey'})
                fdv_list.itemconfig(idx, {'fg': 'black'})
            else:
                fdv_list.itemconfig(idx, {'fg': 'black'})
                mktcap_list.itemconfig(idx, {'fg': 'black'})
        except ValueError:
            # If conversion fails, set both to black
            fdv_list.itemconfig(idx, {'fg': 'black'})
            mktcap_list.itemconfig(idx, {'fg': 'black'})
    
    root.update_idletasks()  # Force GUI update

def fetch_dex_changes():
    global constants, h6_changes, run_count
    run_count += 1
    if run_count > 2:
        h6_changes.clear()
        print("Clearing h6_changes.")
    else:
        print("Run {}: Not clearing h6_changes.".format(run_count))

    for idx, (name, address) in enumerate(constants.items()):
        print("Processing {}: {}".format(name, address))
        token_dex = get_token_dex(address)
        token_info = get_token_scan(address)
        if token_dex:
            h6_price_change = token_dex.get('h6_price_change', 0)
            print("h6_price_change for {}: {}".format(address, h6_price_change))
            color = "green" if h6_price_change > 0 else "red" if h6_price_change < 0 else "black"
            
            # Update price and color
            price_usd = token_dex.get('priceUsd', 0)
            price_formatted = "${:,.4f}".format(price_usd) if price_usd else "N/A"
            price_list.delete(idx)
            price_list.insert(idx, price_formatted)
            update_color_and_tooltip(idx, color, h6_price_change)
            
            # Update FDV
            fdv = token_dex.get('fdv', 0)
            fdv_formatted = "${:,.2f}".format(fdv) if fdv > 0 else "N/A"
            fdv_list.delete(idx)
            fdv_list.insert(idx, fdv_formatted)
            
            # Calculate and update Market Cap
            if token_info:
                total_supply = float(token_info.get('total_supply', 0))
                decimals = int(token_info.get('decimals', 18))
                market_cap = (total_supply / (10 ** decimals)) * price_usd
                market_cap_formatted = "${:,.2f}".format(market_cap) if market_cap > 0 else "N/A"
            else:
                market_cap_formatted = "N/A"
            mktcap_list.delete(idx)
            mktcap_list.insert(idx, market_cap_formatted)
        else:
            print("No new data for {}: using existing data".format(address))
            existing_h6_change = h6_changes.get(idx, 0)
            color = "green" if existing_h6_change > 0 else "red" if existing_h6_change < 0 else "black"
            update_color_and_tooltip(idx, color, existing_h6_change)

    # Update FDV and Market Cap colors
    update_fdv_mktcap_colors()

    print("Completed fetching and updating price changes.")
    root.after(3600000, fetch_dex_changes)  # Reschedule to run after 1 hour

def start_fetch_dex_changes():
    print("start_fetch_dex_changes called")
    thread = threading.Thread(target=fetch_dex_changes)
    thread.daemon = True
    thread.start()

def update_total_usd(window, name, symbol):
    total_usd = 0.0
    for i in range(liq_list.size()):
        item_text = liq_list.get(i).replace("$", "").replace(",", "")
        try:
            total_usd += float(item_text)
        except ValueError:
            continue
    window.title("{} - {} - Liquidity - ${:,.2f}".format(name, symbol, total_usd))

def update_missing_info():
    for i in range(contracts_list.size()):
        contract_name = contracts_list.get(i)
        symbol_info = symbol_list.get(i)

        if "Unnamed_" in contract_name or "None - " in symbol_info:
            if not symbol_info.endswith("Token Info Not Available"):
                contracts_list.delete(i)
                contracts_list.insert(i, symbol_info.split(' - ')[0])

            if symbol_info.startswith("None - "):
                symbol_list.delete(i)
                symbol_list.insert(i, contract_name)


def update_list():
    global constants, h6_changes, total_supplies, royalty_tokens
    
    # First check for custom.txt
    try:
        if os.path.exists("custom.txt"):
            print("Found custom.txt, using custom address list...")
            constants = OrderedDict()
            with open("custom.txt", 'r') as file:
                for line in file:
                    address = line.strip()
                    if address.startswith("0x") and len(address) == 42:
                        # Use address as both key and value in constants
                        constants[address] = address
            if constants:
                print("Loaded {} addresses from custom.txt".format(len(constants)))
                royalty_tokens = OrderedDict()  # Empty for custom list
            else:
                print("No valid addresses found in custom.txt, falling back to addresses.sol")
                return fetch_addresses_sol()
        else:
            return fetch_addresses_sol()

    except Exception as e:
        print("Error reading custom.txt: {}".format(e))
        return fetch_addresses_sol()

    # Process regular tokens
    for name, address in constants.items():
        process_token(name, address, is_royalty=False)

    update_fdv_mktcap_colors()
    print("Finished populating lists.")

def fetch_addresses_sol():
    # Move existing addresses.sol logic here
    temp_file_path = "temp_addresses.sol"
    github_url = "https://github.com/busytoby/atropa_pulsechain/blob/main/solidity/addresses.sol"
    print("Downloading file from {}".format(github_url))
    response = simple_get(github_url)
    if response['status_code'] == 200:
        with open(temp_file_path, 'wb') as file:
            file.write(response['content'].encode('utf-8'))
        print("File successfully downloaded.")
        global constants, royalty_tokens
        constants, royalty_tokens = extract_constants_from_file(temp_file_path)
        print("Tokens extracted successfully. Found {} constants and {} royalty tokens.".format(len(constants), len(royalty_tokens)))
        os.remove(temp_file_path)
        
        # Process regular tokens
        for name, address in constants.items():
            process_token(name, address, is_royalty=False)

        # Process royalty tokens
        for address, name in royalty_tokens.items():
            process_token(name, address, is_royalty=True)
            
        update_fdv_mktcap_colors()
    else:
        print("Failed to download file: HTTP {}".format(response['status_code']))

def process_token(name, address, is_royalty=False):
    token_info = get_token_scan(address)
    token_dex = get_token_dex(address)

    # Try to get token name and symbol
    token_name = token_info.get('name')
    token_symbol = token_info.get('symbol', '')

    # If PulseScan didn't provide name/symbol, check DexScreener
    if not token_name or token_name == 'Token Info Not Available':
        if token_dex and 'baseToken' in token_dex:
            print("[Data] Using DexScreener baseToken data for", address)
            token_name = token_dex['baseToken'].get('name')
            token_symbol = token_dex['baseToken'].get('symbol', '')

    # For display in first list (contracts_list)
    display_name = ''
    if token_name and token_name != 'Token Info Not Available':
        display_name = token_name
    elif not is_royalty:
        display_name = address

    # Insert into lists
    if is_royalty:
        contracts_list.insert(tk.END, display_name)
        contracts_list.itemconfig(tk.END, {'fg': 'purple'})
    else:
        contracts_list.insert(tk.END, display_name)

    addresses_list.insert(tk.END, address)
    
    # For name/symbol list, use address as fallback if no name available
    final_name = token_name if token_name and token_name != 'Token Info Not Available' else address
    symbol_list.insert(tk.END, u"{} - {}".format(final_name, token_symbol))

    # Rest of function remains the same...

    price_usd = token_dex.get('priceUsd', 0)
    price_formatted = "${:,.4f}".format(float(price_usd)) if price_usd else "N/A"
    price_list.insert(tk.END, price_formatted)

    h6_price_change = token_dex.get('h6_price_change', 0)
    h6_changes[contracts_list.size() - 1] = h6_price_change
    
    color = "green" if h6_price_change > 0 else "red" if h6_price_change < 0 else "black"
    price_list.itemconfig(tk.END, {'fg': color})

    if 'total_supply' in token_info and price_usd:
        total_supply = float(token_info.get('total_supply', 0))
        price_usd = float(price_usd)
        decimals = int(token_info.get('decimals', 18))
        market_cap = (total_supply / (10 ** decimals)) * price_usd
        market_cap_formatted = "${:,.2f}".format(market_cap)
    else:
        market_cap_formatted = "N/A"
    mktcap_list.insert(tk.END, market_cap_formatted)

    fdv = float(token_dex.get('fdv', 0)) if 'fdv' in token_dex else 0
    fdv_formatted = "${:,.2f}".format(fdv) if fdv > 0 else "N/A"
    fdv_list.insert(tk.END, fdv_formatted)

    volume_h24 = float(token_dex.get('volume_h24', 0)) if 'volume_h24' in token_dex else 0
    volume_h24_formatted = "${:,.2f}".format(volume_h24) if volume_h24 > 0 else "N/A"
    volume_list.insert(tk.END, volume_h24_formatted)

def simple_get(url, headers=None):
    if headers is None:
        headers = {'User-Agent': 'Mozilla/5.0'}
    request = urllib2.Request(url, headers=headers)
    context = ssl.create_default_context(cafile='cacert-2024-03-11.pem')
    try:
        response = urllib2.urlopen(request, context=context)
        content = response.read().decode('utf-8')
        return {'status_code': response.getcode(), 'content': content}
    except urllib2.HTTPError as e:
        print("HTTP Error:", e.code, e.reason)
        print("Response Headers:", e.headers)
        return {'status_code': e.code, 'content': e.read().decode('utf-8')}
    except urllib2.URLError as e:
        print("URL Error:", e.code, e.reason)
        print("Response Headers:", e.headers)
        return {'status_code': 0, 'content': str(e)}

def double_click(event):
    index = contracts_list.nearest(event.y)
    name_symbol = symbol_list.get(index)
    if ' - ' in name_symbol:
        parts = name_symbol.split(' - ')
        name = parts[0]
        symbol = parts[1] if len(parts) > 1 else ''
    else:
        name = name_symbol
        symbol = ''

    address = addresses_list.get(index)

    global new_window
    new_window = tk.Toplevel(root) 
    window_color = generate_base_color()
    new_window.base_color = window_color 
    new_window.configure(bg=window_color)
    
    # Get titlebar height after window is created
    root.update_idletasks()
    titlebar_height = root.winfo_rooty() - root.winfo_y()
    
    # Position first sub-window aligned with main window, accounting for titlebar
    x = root.winfo_x()
    y = root.winfo_y() - (200 + titlebar_height)  # Account for window height + titlebar
    new_window.geometry("400x200+{}+{}".format(x, y))
    new_window.minsize(400, 200)

    sub_frame = tk.Frame(new_window, bg=window_color)
    sub_frame.pack(padx=5, pady=5, fill=tk.BOTH, expand=True)

    global qtoken_list, liq_list
    qtoken_list = tk.Listbox(sub_frame, width=30, height=10)
    qtoken_list.grid(row=0, column=0, padx=5, pady=5, sticky=tk.NSEW)
    liq_list = tk.Listbox(sub_frame, width=20, height=10)
    liq_list.grid(row=0, column=1, padx=5, pady=5, sticky=tk.NSEW)

    qtoken_list.bind("<ButtonRelease-1>", sync_lists_on_click)
    liq_list.bind("<ButtonRelease-1>", sync_lists_on_click)
    
    # Add double-click bindings for sub-window lists
    qtoken_list.bind("<Double-1>", lambda e: sub_window_double_click(e, new_window, address))
    liq_list.bind("<Double-1>", lambda e: sub_window_double_click(e, new_window, address))

    api_url = "{}/{}".format(DEXSCREENER_API_BASE_URL, address)
    response = simple_get(api_url)
    if response['status_code'] == 200:
        data = json.loads(response['content'])
        pair_data = data.get("pairs", [])
        populate_liqlists(pair_data, new_window, name, symbol)
        
        # Store pair_data in the listboxes for later use
        qtoken_list.pair_data = pair_data
        liq_list.pair_data = pair_data
    else:
        qtoken_list.insert(tk.END, "Failed to fetch data from API")
        liq_list.insert(tk.END, "Failed to fetch data from API")

    sub_frame.columnconfigure(0, weight=1)
    sub_frame.columnconfigure(1, weight=1)
    sub_frame.rowconfigure(0, weight=1)

def sub_window_double_click(event, parent_window, parent_address):
    index = event.widget.nearest(event.y)
    pair_data = event.widget.pair_data[index]
    
    if event.widget == qtoken_list:
        qtoken_double_click(event, parent_window, parent_address, pair_data)
    else:
        liq_double_click(event, parent_window, parent_address, pair_data)

def liq_double_click(event, parent_window, parent_address, pair_data):
    quote_token = pair_data["quoteToken"]["symbol"]
    base_token = pair_data["baseToken"]["symbol"]
    pair_address = pair_data["pairAddress"]
    
    new_sub_window = tk.Toplevel(parent_window)
    
    if hasattr(parent_window, 'base_color'):
        window_color = generate_shade_of_color(parent_window.base_color, factor=0.8)
    else:
        window_color = generate_base_color()
    new_sub_window.base_color = window_color
    new_sub_window.configure(bg=window_color)

    # Get the spawning window
    source_window = event.widget.master.master
    
    # Get titlebar height
    source_window.update_idletasks()
    titlebar_height = source_window.winfo_rooty() - source_window.winfo_y()

    # Position at the same x as source window, but below it
    x = source_window.winfo_x()
    y = source_window.winfo_y() + source_window.winfo_height() + titlebar_height

    new_sub_window.geometry("350x200+{}+{}".format(x, y))
    new_sub_window.minsize(350, 200)

    sub_frame = tk.Frame(new_sub_window, bg=window_color)
    sub_frame.pack(padx=5, pady=5, fill=tk.BOTH, expand=True)

    sub_qtoken_list = tk.Listbox(sub_frame, width=30, height=10, bg="white")  
    sub_qtoken_list.grid(row=0, column=0, padx=5, pady=5, sticky=tk.NSEW)
    sub_liq_list = tk.Listbox(sub_frame, width=20, height=10, bg="white")  
    sub_liq_list.grid(row=0, column=1, padx=5, pady=5, sticky=tk.NSEW)

    try:
        sub_qtoken_list.insert(tk.END, u"Base Token: {}".format(pair_data['baseToken']['name']))
        sub_qtoken_list.insert(tk.END, u"Quote Token: {}".format(pair_data['quoteToken']['name']))
        sub_qtoken_list.insert(tk.END, "") 
        sub_qtoken_list.insert(tk.END, u"Price: {} {}".format(pair_data['priceNative'], quote_token))
        sub_qtoken_list.insert(tk.END, u"Price USD: ${}".format(pair_data['priceUsd']))
        sub_qtoken_list.insert(tk.END, "") 
        sub_qtoken_list.insert(tk.END, u"24h Volume: ${:,.2f}".format(float(pair_data['volume']['h24'])))
        sub_qtoken_list.insert(tk.END, "")
        sub_qtoken_list.insert(tk.END, u"FDV: ${:,.2f}".format(float(pair_data.get('fdv', 0))))
    except (UnicodeEncodeError, UnicodeDecodeError) as e:
        print("Unicode Error:", e)
        sub_qtoken_list.insert(tk.END, "Error displaying token information")
    except KeyError as e:
        print("Missing data key:", e)
        sub_qtoken_list.insert(tk.END, "Error: Missing data")

    try:
        sub_liq_list.insert(tk.END, "Liquidity (USD):")
        sub_liq_list.insert(tk.END, "${:,.2f}".format(float(pair_data['liquidity']['usd'])))
        sub_liq_list.insert(tk.END, "") 
        sub_liq_list.insert(tk.END, "Base Token Amount:")
        sub_liq_list.insert(tk.END, "{:,.4f}".format(float(pair_data['liquidity']['base'])))
        sub_liq_list.insert(tk.END, "") 
        sub_liq_list.insert(tk.END, "Quote Token Amount:")
        sub_liq_list.insert(tk.END, "{:,.4f}".format(float(pair_data['liquidity']['quote'])))
    except (KeyError, ValueError) as e:
        print("Error processing liquidity data:", e)
        sub_liq_list.insert(tk.END, "N/A")

    sub_frame.columnconfigure(0, weight=1)
    sub_frame.columnconfigure(1, weight=1)
    sub_frame.rowconfigure(0, weight=1)

    try:
        title = u"{}/{} Liquidity".format(
            pair_data['baseToken']['symbol'],
            pair_data['quoteToken']['symbol']
        )
        new_sub_window.title(title)
    except (KeyError, ValueError, UnicodeError) as e:
        print("Error setting window title:", e)
        new_sub_window.title("Trading Pair Details")

def qtoken_double_click(event, parent_window, parent_address, pair_data):
    quote_token = pair_data["quoteToken"]["symbol"]
    quote_token_address = pair_data["quoteToken"]["address"]
    
    new_sub_window = tk.Toplevel(parent_window)
    
    if hasattr(parent_window, 'base_color'):
        window_color = generate_shade_of_color(parent_window.base_color, factor=0.8)
    else:
        window_color = generate_base_color()
    new_sub_window.base_color = window_color
    new_sub_window.configure(bg=window_color)

    # Get titlebar height by comparing window geometry with client geometry
    parent_window.update_idletasks()  # Ensure geometry is current
    titlebar_height = parent_window.winfo_rooty() - parent_window.winfo_y()

    # Get position of spawning window
    source_x = event.widget.master.master.winfo_x()  # Navigate up to window from listbox
    source_y = event.widget.master.master.winfo_y()

    # Position next to the spawning window, at same height
    x = source_x + event.widget.master.master.winfo_width()
    y = source_y  # Maintain same Y as spawning window

    new_sub_window.geometry("350x200+{}+{}".format(x, y))
    new_sub_window.minsize(350, 200)

    sub_frame = tk.Frame(new_sub_window, bg=window_color)
    sub_frame.pack(padx=5, pady=5, fill=tk.BOTH, expand=True)

    sub_qtoken_list = tk.Listbox(sub_frame, width=30, height=10, bg="white")  
    sub_qtoken_list.grid(row=0, column=0, padx=5, pady=5, sticky=tk.NSEW)
    sub_liq_list = tk.Listbox(sub_frame, width=20, height=10, bg="white")
    sub_liq_list.grid(row=0, column=1, padx=5, pady=5, sticky=tk.NSEW)

    # Get trading pairs where the quote token is the base token
    api_url = "{}/{}".format(DEXSCREENER_API_BASE_URL, quote_token_address)
    response = simple_get(api_url)
    if response['status_code'] == 200:
        try:
            data = json.loads(response['content'])
            total_liquidity = 0
            if 'pairs' in data and data['pairs']:
                # Store pairs data for double-click access
                sub_qtoken_list.pairs_data = data['pairs']
                sub_liq_list.pairs_data = data['pairs']
                
                for pair in data['pairs']:
                    new_quote_symbol = pair['quoteToken']['symbol']
                    price_native = pair['priceNative']
                    price_display = u"{} - {}".format(new_quote_symbol, price_native)
                    sub_qtoken_list.insert(tk.END, price_display)
                    
                    liquidity_usd = pair.get('liquidity', {}).get('usd', 0)
                    total_liquidity += liquidity_usd
                    sub_liq_list.insert(tk.END, "${:,.2f}".format(liquidity_usd))

                # QToken list handler - continues path tracing
                def handle_qtoken_double_click(event):
                    idx = event.widget.nearest(event.y)
                    pairs_data = event.widget.pairs_data
                    if idx < len(pairs_data):
                        qtoken_double_click(event, new_sub_window, quote_token_address, pairs_data[idx])

                # Liq list handler - shows detailed liquidity info
                def handle_liq_double_click(event):
                    idx = event.widget.nearest(event.y)
                    pairs_data = event.widget.pairs_data
                    if idx < len(pairs_data):
                        liq_double_click(event, new_sub_window, quote_token_address, pairs_data[idx])

                # Bind appropriate handlers to each list
                sub_qtoken_list.bind("<Double-1>", handle_qtoken_double_click)
                sub_liq_list.bind("<Double-1>", handle_liq_double_click)

                # Selection sync
                def sync_sub_lists(event):
                    sender = event.widget
                    idx = sender.nearest(event.y)
                    other_list = sub_liq_list if sender == sub_qtoken_list else sub_qtoken_list
                    
                    other_list.selection_clear(0, tk.END)
                    other_list.selection_set(idx)
                    
                    sender.selection_clear(0, tk.END)
                    sender.selection_set(idx)

                sub_qtoken_list.bind("<ButtonRelease-1>", sync_sub_lists)
                sub_liq_list.bind("<ButtonRelease-1>", sync_sub_lists)

            else:
                sub_qtoken_list.insert(tk.END, "No trading pairs found")
                sub_liq_list.insert(tk.END, "N/A")

            try:
                window_title = u"{} Trading Pairs - Total: ${:,.2f}".format(quote_token, total_liquidity)
                new_sub_window.title(window_title)
            except UnicodeError:
                new_sub_window.title("Trading Pairs")

        except Exception as e:
            print("Error processing pair data:", e)
            sub_qtoken_list.insert(tk.END, "Error processing data")
            sub_liq_list.insert(tk.END, "Error")
    else:
        sub_qtoken_list.insert(tk.END, "Failed to fetch data")
        sub_liq_list.insert(tk.END, "N/A")

    sub_frame.columnconfigure(0, weight=1)
    sub_frame.columnconfigure(1, weight=1)
    sub_frame.rowconfigure(0, weight=1)

def populate_sub_window_lists(qtoken_list, liq_list, data):
    total_liquidity = 0
    
    
    if isinstance(data, dict) and 'priceUsd' in data:
        qtoken_list.insert(tk.END, "Price: ${:.4f}".format(data["priceUsd"]))
        qtoken_list.insert(tk.END, "24h Change: {:.2f}%".format(data.get("h6_price_change", 0)))
        
        liq_list.insert(tk.END, "Vol: ${:,.2f}".format(data["volume_h24"]))
        liq_list.insert(tk.END, "FDV: ${:,.2f}".format(data["fdv"]))
        
        total_liquidity = data["volume_h24"]  
    
    
    else:
        for pair in data:
            quote_token = pair["quoteToken"]["symbol"]
            price_native = pair["priceNative"]
            qtoken_list.insert(tk.END, "{} - {}".format(quote_token, price_native))
            
            liquidity = float(pair["liquidity"]["usd"])
            liq_list.insert(tk.END, "${:,.2f}".format(liquidity))
            total_liquidity += liquidity

    
    if qtoken_list.master and qtoken_list.master.master:
        qtoken_list.master.master.title("Total Value: ${:,.2f}".format(total_liquidity))
        
def populate_liqlists(pair_data, window, name, symbol):
    qtoken_list.delete(0, tk.END)
    liq_list.delete(0, tk.END)
    total_usd = 0.0

    for pair in pair_data:
        quote_token = pair["quoteToken"]["symbol"]
        if isinstance(quote_token, str):
            quote_token = quote_token.decode('utf-8')

        price_native = u"{} - {}".format(quote_token, pair["priceNative"])
        liquidity_usd = pair.get("liquidity", {}).get("usd", 0)
        total_usd += liquidity_usd

        qtoken_list.insert(tk.END, price_native)
        liq_list.insert(tk.END, "${:.2f}".format(liquidity_usd))

    total_formatted = "${:,.4f}".format(total_usd)

    try:
        window_title = u"{} - {} - Total: {}".format(name, symbol, total_formatted)
        window.title(window_title)
    except UnicodeError as e:
        print("Unicode Error when updating the window title:", e)
        window.title("Details Error")

def sync_lists_on_click(event):
    sender = event.widget
    idx = sender.curselection()[0]

    contracts_list.selection_clear(0, tk.END)
    addresses_list.selection_clear(0, tk.END)
    symbol_list.selection_clear(0, tk.END)
    price_list.selection_clear(0, tk.END)
    fdv_list.selection_clear(0, tk.END)
    mktcap_list.selection_clear(0, tk.END)
    volume_list.selection_clear(0, tk.END)

    contracts_list.selection_set(idx)
    addresses_list.selection_set(idx)
    symbol_list.selection_set(idx)
    price_list.selection_set(idx)
    fdv_list.selection_set(idx)
    mktcap_list.selection_set(idx)
    volume_list.selection_set(idx)
    sender.selection_set(idx)

    contracts_list.see(idx)
    addresses_list.see(idx)
    symbol_list.see(idx)
    price_list.see(idx)
    fdv_list.see(idx)
    mktcap_list.see(idx)
    volume_list.see(idx)

def update_lists_scroll(*args):
    contracts_list.yview(*args)
    addresses_list.yview(*args)
    symbol_list.yview(*args)
    price_list.yview(*args)
    fdv_list.yview(*args)
    mktcap_list.yview(*args)
    volume_list.yview(*args)

# Create main window
root = tk.Tk()
root.title("Atropa Console")

# Configure window width
root.minsize(1000, 200)

# Create a frame
frame = tk.Frame(root)
frame.pack(padx=10, pady=10, fill=tk.BOTH, expand=True)

# Define all Listboxes
contracts_list = tk.Listbox(frame, width=24, height=20)
addresses_list = tk.Listbox(frame, width=46, height=20)
symbol_list = tk.Listbox(frame, width=42, height=20)
price_list = tk.Listbox(frame, width=13, height=20)
fdv_list = tk.Listbox(frame, width=20, height=20)
mktcap_list = tk.Listbox(frame, width=20, height=20)
volume_list = tk.Listbox(frame, width=20, height=20)

# Grid placement
contracts_list.grid(row=0, column=0, padx=5, pady=5, sticky=tk.NS)
addresses_list.grid(row=0, column=1, padx=5, pady=5, sticky=tk.NS)
symbol_list.grid(row=0, column=2, padx=5, pady=5, sticky=tk.NS)
price_list.grid(row=0, column=3, padx=5, pady=5, sticky=tk.NS)
fdv_list.grid(row=0, column=4, padx=5, pady=5, sticky=tk.NS)
mktcap_list.grid(row=0, column=5, padx=5, pady=5, sticky=tk.NS)
volume_list.grid(row=0, column=6, padx=5, pady=5, sticky=tk.NS)

# Tooltip text
create_dynamic_tooltip(contracts_list, lambda idx: "Address Name")
create_dynamic_tooltip(addresses_list, lambda idx: "PulseChain Address")
create_dynamic_tooltip(symbol_list, lambda idx: "Token Name and Symbol.")
create_dynamic_tooltip(price_list, lambda idx: "6hr: {:.2f}%".format(h6_changes.get(idx, 0)))
create_dynamic_tooltip(fdv_list, lambda idx: "Fully Diluted Valuation (FDV)")
create_dynamic_tooltip(mktcap_list, lambda idx: "Supply: {}".format(total_supplies.get(addresses_list.get(idx), 'N/A')))
create_dynamic_tooltip(volume_list, lambda idx: "24-Hour Volume")

# Scrollbar configuration
scrollbar = tk.Scrollbar(frame, command=update_lists_scroll)
scrollbar.grid(row=0, column=7, sticky=tk.NS)

# Configuring scrolling for all lists
contracts_list.config(yscrollcommand=scrollbar.set)
addresses_list.config(yscrollcommand=scrollbar.set)
symbol_list.config(yscrollcommand=scrollbar.set)
price_list.config(yscrollcommand=scrollbar.set)
fdv_list.config(yscrollcommand=scrollbar.set)
mktcap_list.config(yscrollcommand=scrollbar.set)
volume_list.config(yscrollcommand=scrollbar.set)

# Configure grid weights for resizing
for i in range(7):
    frame.columnconfigure(i, weight=1)
frame.rowconfigure(0, weight=1)

print("GUI setup complete. Starting data update...")

print("GUI setup complete. Starting data update...")

# Setup the initial data update functions if needed
update_list()
update_missing_info()

# Schedule the first update after 1 hour (3600000 milliseconds)
root.after(3600000, fetch_dex_changes)

print("Initial data loaded. Next update scheduled in 1 hour.")

# Double-click event to spawn a new window
# Double-click event to spawn a new window
contracts_list.bind("<Double-1>", double_click)
addresses_list.bind("<Double-1>", double_click)
symbol_list.bind("<Double-1>", double_click)
price_list.bind("<Double-1>", double_click)
mktcap_list.bind("<Double-1>", double_click)
fdv_list.bind("<Double-1>", double_click)
volume_list.bind("<Double-1>", double_click)

contracts_list.bind("<ButtonRelease-1>", sync_lists_on_click)
addresses_list.bind("<ButtonRelease-1>", sync_lists_on_click)
symbol_list.bind("<ButtonRelease-1>", sync_lists_on_click)
price_list.bind("<ButtonRelease-1>", sync_lists_on_click)
fdv_list.bind("<ButtonRelease-1>", sync_lists_on_click)
mktcap_list.bind("<ButtonRelease-1>", sync_lists_on_click)
volume_list.bind("<ButtonRelease-1>", sync_lists_on_click)

print("All setup complete. Starting main loop...")


root.mainloop()