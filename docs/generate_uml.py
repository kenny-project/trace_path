#!/usr/bin/env python3
"""
Generate UML diagrams for trace_path Flutter project using matplotlib.
Outputs: class_diagram.png, sequence_diagram.png, architecture_diagram.png
"""

import matplotlib
matplotlib.use('Agg')
matplotlib.rcParams['font.family'] = 'Noto Sans CJK SC, Noto Sans CJK SC Bold, sans-serif'
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.font_manager as fm
import numpy as np

# Register CJK font
cjk_font_path = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'
try:
    fm.fontManager.addfont(cjk_font_path)
    prop = fm.FontProperties(fname=cjk_font_path)
    CJK_FONT = prop.get_name()
    matplotlib.rcParams['font.family'] = CJK_FONT
    plt.rcParams['font.family'] = CJK_FONT
    print(f"Using CJK font: {CJK_FONT}")
except Exception as e:
    print(f"CJK font load failed: {e}, falling back to sans-serif")
    CJK_FONT = 'sans-serif'
    prop = None

# ========== Color Palette ==========
COLORS = {
    'class_bg': '#E8F4FD',      # light blue for classes
    'abstract_bg': '#FFF3E0',    # orange-ish for abstract classes
    'interface_bg': '#E8F5E9',  # green-ish for interfaces
    'singleton_bg': '#F3E5F5',   # purple-ish for singletons
    'model_bg': '#FFFDE7',      # yellow for models
    'service_bg': '#E3F2FD',    # blue for services
    'border': '#1565C0',
    'border_light': '#90CAF9',
    'header': '#1565C0',
    'text': '#212121',
    'arrow': '#424242',
    'section_bg': '#FAFAFA',
    'layer_presentation': '#BBDEFB',
    'layer_business': '#B2DFDB',
    'layer_data': '#FFCCBC',
    'layer_native': '#C8E6C9',
}

def draw_class_box(ax, x, y, w, h, name, attrs=None, methods=None,
                   bg_color=None, header_color=None, is_abstract=False,
                   stereotype=None):
    """Draw a UML class box."""
    if bg_color is None:
        bg_color = COLORS['class_bg']
    if header_color is None:
        header_color = COLORS['header']

    # Main box
    box = FancyBboxPatch((x, y), w, h,
                         boxstyle="round,pad=0.02",
                         facecolor=bg_color,
                         edgecolor=COLORS['border'],
                         linewidth=1.5,
                         zorder=3)
    ax.add_patch(box)

    # Header background
    header_h = h * 0.28 if attrs or methods else h * 0.55
    header = FancyBboxPatch((x, y + h - header_h), w, header_h,
                            boxstyle="round,pad=0.01",
                            facecolor=header_color,
                            edgecolor='none',
                            linewidth=0,
                            zorder=4)
    ax.add_patch(header)

    # Header text
    header_text = ''
    if stereotype:
        header_text = f'<<{stereotype}>>\n{name}'
    else:
        header_text = name

    ax.text(x + w/2, y + h - header_h/2, header_text,
            ha='center', va='center', fontsize=8.5, fontweight='bold',
            color='white', zorder=5)

    # Divider lines
    content_h = h - header_h
    if attrs and methods:
        mid_y = y + h - header_h - content_h * 0.45
    elif attrs or methods:
        mid_y = y + h - header_h - content_h * 0.5
    else:
        mid_y = None

    if attrs:
        attr_text = '\n'.join(attrs[:8])  # limit to 8
        ax.text(x + 0.08, y + h - header_h - 0.12, attr_text,
                ha='left', va='top', fontsize=7, color=COLORS['text'], zorder=5)

    if methods:
        method_text = '\n'.join(methods[:8])
        start_y = mid_y + 0.05 if mid_y else y + 0.1
        ax.text(x + 0.08, start_y, method_text,
                ha='left', va='top', fontsize=7, color=COLORS['text'], zorder=5)

    # Draw divider
    if mid_y:
        ax.plot([x, x+w], [mid_y, mid_y], color=COLORS['border_light'],
                linewidth=0.8, zorder=4)


def arrow(ax, x1, y1, x2, y2, label='', style='-', color=None, label_offset=(0,0.15)):
    """Draw an arrow with optional label."""
    if color is None:
        color = COLORS['arrow']
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color,
                               lw=1.3, connectionstyle='arc3,rad=0'),
                zorder=2)
    if label:
        mx = (x1 + x2) / 2 + label_offset[0]
        my = (y1 + y2) / 2 + label_offset[1]
        ax.text(mx, my, label, ha='center', va='bottom', fontsize=7,
                color=color, zorder=6,
                bbox=dict(boxstyle='round,pad=0.1', facecolor='white',
                         edgecolor='none', alpha=0.8))


def diamond(ax, cx, cy, size=0.18):
    """Draw a diamond (for composition/aggregation)."""
    diamond = plt.Polygon([[cx, cy+size], [cx+size, cy],
                            [cx, cy-size], [cx-size, cy]],
                           facecolor=COLORS['class_bg'],
                           edgecolor=COLORS['border'],
                           linewidth=1.2, zorder=3)
    ax.add_patch(diamond)


def draw_composition(ax, x1, y1, x2, y2, label='', color=None):
    """Draw a composition arrow (filled diamond at source)."""
    if color is None:
        color = COLORS['arrow']
    # Draw line
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color,
                               lw=1.3, connectionstyle='arc3,rad=0'),
                zorder=2)
    # Draw filled diamond at source
    dx = x2 - x1
    dy = y2 - y1
    length = (dx**2 + dy**2)**0.5
    if length == 0:
        return
    ux, uy = dx/length, dy/length
    cx, cy = x1 + ux*0.15, y1 + uy*0.15
    size = 0.12
    diamond = plt.Polygon([[cx, cy+size], [cx+size*0.7, cy],
                            [cx, cy-size], [cx-size*0.7, cy]],
                           facecolor=color, edgecolor=color,
                           linewidth=1, zorder=4)
    ax.add_patch(diamond)
    if label:
        mx = (x1+x2)/2
        my = (y1+y2)/2 + 0.12
        ax.text(mx, my, label, ha='center', va='bottom', fontsize=6.5,
                color=color, zorder=6,
                bbox=dict(boxstyle='round,pad=0.1', facecolor='white',
                         edgecolor='none', alpha=0.8))


def draw_aggregate(ax, x1, y1, x2, y2, label=''):
    """Draw an aggregation arrow (hollow diamond at source)."""
    color = COLORS['arrow']
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color,
                               lw=1.3, connectionstyle='arc3,rad=0'),
                zorder=2)
    dx = x2 - x1
    dy = y2 - y1
    length = (dx**2 + dy**2)**0.5
    if length == 0:
        return
    ux, uy = dx/length, dy/length
    cx, cy = x1 + ux*0.15, y1 + uy*0.15
    size = 0.12
    diamond = plt.Polygon([[cx, cy+size], [cx+size*0.7, cy],
                            [cx, cy-size], [cx-size*0.7, cy]],
                           facecolor='white', edgecolor=color,
                           linewidth=1, zorder=4)
    ax.add_patch(diamond)
    if label:
        mx = (x1+x2)/2
        my = (y1+y2)/2 + 0.12
        ax.text(mx, my, label, ha='center', va='bottom', fontsize=6.5,
                color=color, zorder=6,
                bbox=dict(boxstyle='round,pad=0.1', facecolor='white',
                         edgecolor='none', alpha=0.8))


def draw_dependency(ax, x1, y1, x2, y2, label=''):
    """Draw a dashed dependency arrow."""
    color = '#78909C'
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color,
                               lw=1.1, linestyle='dashed',
                               connectionstyle='arc3,rad=0'),
                zorder=2)
    if label:
        mx = (x1+x2)/2
        my = (y1+y2)/2 + 0.12
        ax.text(mx, my, label, ha='center', va='bottom', fontsize=6.5,
                color=color, zorder=6,
                bbox=dict(boxstyle='round,pad=0.1', facecolor='white',
                         edgecolor='none', alpha=0.8))


# ============================================================
# 1. CLASS DIAGRAM
# ============================================================
def generate_class_diagram():
    fig, ax = plt.subplots(figsize=(22, 16))
    ax.set_xlim(0, 22)
    ax.set_ylim(0, 16)
    ax.axis('off')
    ax.set_facecolor('#FAFAFA')
    fig.patch.set_facecolor('#FAFAFA')

    # Title
    ax.text(11, 15.5, 'trace_path 核心服务类图', ha='center', va='center',
            fontsize=16, fontweight='bold', color='#1565C0')
    ax.text(11, 15.1, 'Core Service Class Diagram', ha='center', va='center',
            fontsize=10, color='#757575', style='italic')

    # ---- LAYOUT (units in data coords, 1 unit ~ some cm) ----
    # 4 columns: singleton services | abstract/interface | implementations | models

    # Column x centers
    cx1, cx2, cx3, cx4 = 3.5, 8.0, 13.0, 18.5
    # Row y (top to bottom)
    row1 = 13.5  # BackgroundLocationService (top)
    row2 = 10.0  # LocationProvider / TrackStorage
    row3 = 6.5   # Geolocator / Native / Compressed / LocalCsv
    row4 = 3.0   # Models: Friend, LocationEvent, User

    bw, bh = 3.2, 2.8  # box width/height

    # ---- Singletons (column 1) ----
    draw_class_box(ax, cx1-bw/2, row1-bh/2, bw, bh,
                   'BackgroundLocationService',
                   attrs=[
                       '- _settingsService',
                       '- _userService',
                       '- _errorLogger',
                       '- _locationProvider',
                       '- _subscribers[]',
                       '- _isTracking',
                       '- _intervalSeconds',
                   ],
                   methods=[
                       '+ start()',
                       '+ stop()',
                       '+ subscribe(cb)',
                       '+ _broadcast()',
                       '+ getCurrentPosition()',
                   ],
                   bg_color='#E1F5FE',
                   header_color='#0277BD',
                   stereotype='Singleton')

    draw_class_box(ax, cx1-bw/2, row2-bh/2+0.5, bw, bh,
                   'TrackRecorder',
                   attrs=['- _storage: TrackStorage'],
                   methods=[
                       '+ record(position)',
                       '+ readDay(phone, y,m,d)',
                       '+ setStorage(storage)',
                   ],
                   bg_color='#E1F5FE',
                   header_color='#0277BD',
                   stereotype='Singleton')

    draw_class_box(ax, cx1-bw/2, row3-bh/2+0.5, bw, bh,
                   'FriendService',
                   attrs=['- _friends[]', '- _storage: FriendStorage'],
                   methods=[
                       '+ addFriend()',
                       '+ removeFriend()',
                       '+ updateFriendLocation()',
                       '+ getFriends()',
                   ],
                   bg_color='#E1F5FE',
                   header_color='#0277BD',
                   stereotype='Singleton')

    draw_class_box(ax, cx1-bw/2, row4+1.2, bw, bh*0.7,
                   'UserService',
                   attrs=['- _currentUser', '- _storage: UserStorage'],
                   methods=[
                       '+ saveUser()',
                       '+ clearUser()',
                       '+ isLoggedIn',
                       '+ currentPhoneNumber',
                   ],
                   bg_color='#E1F5FE',
                   header_color='#0277BD',
                   stereotype='Singleton')

    # ---- Abstract/Interfaces (column 2) ----
    draw_class_box(ax, cx2-bw/2, row2-bh/2, bw, bh,
                   'LocationProvider',
                   attrs=[],
                   methods=[
                       '+ getCurrentPosition()',
                       '+ checkPermission()',
                       '+ isLocationServiceEnabled()',
                       '+ dispose()',
                   ],
                   bg_color='#FFF3E0',
                   header_color='#E65100',
                   stereotype='abstract')

    draw_class_box(ax, cx2-bw/2, row3-bh/2, bw, bh,
                   'TrackStorage',
                   attrs=[],
                   methods=[
                       '+ write(phone, point)',
                       '+ readDay(phone,y,m,d)',
                       '+ deleteDay(phone,y,m,d)',
                       '+ syncToServer()',
                       '+ pullFromServer()',
                   ],
                   bg_color='#FFF3E0',
                   header_color='#E65100',
                   stereotype='abstract')

    draw_class_box(ax, cx2-bw/2, row4+0.8, bw, bh*0.85,
                   'FriendStorage',
                   attrs=[],
                   methods=[
                       '+ load()',
                       '+ save(friends)',
                       '+ clear()',
                   ],
                   bg_color='#E8F5E9',
                   header_color='#2E7D32',
                   stereotype='interface')

    # ---- Implementations (column 3) ----
    draw_class_box(ax, cx3-bw/2+0.3, row2-bh/2, bw, bh,
                   'GeolocatorLocationProvider',
                   attrs=['- _errorLogger'],
                   methods=[
                       '+ getCurrentPosition()',
                       '+ checkPermission()',
                       '+ isLocationServiceEnabled()',
                   ],
                   bg_color='#E3F2FD',
                   header_color='#1565C0')

    draw_class_box(ax, cx3-bw/2-1.8, row3-bh/2, bw, bh,
                   'CompressedTrackStorage',
                   attrs=['- _manager'],
                   methods=[
                       '+ write()',
                       '+ readDay()',
                       '+ deleteDay()',
                       '+ getCompressionRatio()',
                   ],
                   bg_color='#E3F2FD',
                   header_color='#1565C0')

    draw_class_box(ax, cx3-bw/2+2.1, row3-bh/2, bw, bh,
                   'LocalCsvStorage',
                   attrs=['- _manager'],
                   methods=[
                       '+ write()',
                       '+ readDay()',
                       '+ deleteDay()',
                   ],
                   bg_color='#E3F2FD',
                   header_color='#1565C0')

    # ---- Models (column 4) ----
    draw_class_box(ax, cx4-bw/2, row2-bh/2+1.5, bw, bh*0.9,
                   'LocationEvent',
                   attrs=['- type', '- position', '- errorMessage'],
                   methods=[
                       '+ position()',
                       '+ error()',
                       '+ serviceStart()',
                       '+ serviceStop()',
                   ],
                   bg_color='#FFFDE7',
                   header_color='#F57F17',
                   stereotype='Model')

    draw_class_box(ax, cx4-bw/2, row3-bh/2+0.8, bw, bh*0.9,
                   'Friend',
                   attrs=['- phoneNumber', '- name', '- emoji', '- lat/lng'],
                   methods=['+ toJson()', '+ fromJson()', '+ copyWith()'],
                   bg_color='#FFFDE7',
                   header_color='#F57F17',
                   stereotype='Model')

    draw_class_box(ax, cx4-bw/2, row4+0.8, bw, bh*0.7,
                   'TrackPoint',
                   attrs=['- timestamp', '- lat/lng', '- altitude', '- speed'],
                   methods=['+ fromPosition()', '+ toLatLng()', '+ toCsvLine()'],
                   bg_color='#FFFDE7',
                   header_color='#F57F17',
                   stereotype='Model')

    # ---- ARROWS ----
    # BackgroundLocationService -> LocationProvider (uses, dashed)
    draw_dependency(ax, cx1-bw/2, row1-bh*0.4, cx2-bw/2+bw, row2,
                    'uses (delegates)')

    # BackgroundLocationService -> TrackRecorder (calls)
    draw_dependency(ax, cx1, row1-bh/2, cx1, row2-bh/2+0.5+bh*0.5,
                    'calls.record()')

    # TrackRecorder -> TrackStorage (has, composition)
    draw_composition(ax, cx1-bw*0.2, row2-bh*0.3, cx2-bw/2+bw, row3-bh/2+bh,
                     'stores')

    # GeolocatorLocationProvider implements LocationProvider
    draw_dependency(ax, cx3-bw/2+0.3, row2-bh/2, cx2-bw/2+bw, row2-bh/2,
                    'implements')

    # CompressedTrackStorage implements TrackStorage
    draw_dependency(ax, cx3-bw/2-1.8, row3-bh/2, cx2-bw/2, row3-bh/2,
                    'implements')

    # LocalCsvStorage implements TrackStorage
    draw_dependency(ax, cx3-bw/2+2.1, row3-bh/2, cx2-bw/2+bw, row3-bh/2+bh,
                    'implements')

    # FriendService -> FriendStorage (composition)
    draw_composition(ax, cx1-bw*0.2, row3-bh*0.4+0.5, cx2-bw/2, row4+0.8+bh*0.85,
                     'stores')

    # UserService -> User (model)
    arrow(ax, cx1-bw*0.3, row4+1.2, cx4-bw/2+bw, row4+1.2+0.2,
          'manages')

    # Legend
    legend_x, legend_y = 0.5, 2.5
    ax.text(legend_x, legend_y+0.5, '图例 Legend:', fontsize=8, fontweight='bold')
    ax.plot([legend_x, legend_x+0.6], [legend_y, legend_y],
            color=COLORS['arrow'], lw=1.5, zorder=5)
    ax.annotate('', xy=(legend_x+0.6, legend_y), xytext=(legend_x, legend_y),
                arrowprops=dict(arrowstyle='->', color=COLORS['arrow'], lw=1.5), zorder=5)
    ax.text(legend_x+0.7, legend_y, '依赖 (uses)', fontsize=7.5, va='center')

    ax.plot([legend_x, legend_x+0.6], [legend_y-0.4, legend_y-0.4],
            color=COLORS['arrow'], lw=1.5, zorder=5)
    diamond2 = plt.Polygon([[legend_x, legend_y-0.4+0.1],
                              [legend_x+0.12*0.7, legend_y-0.4],
                              [legend_x, legend_y-0.4-0.1],
                              [legend_x-0.12*0.7, legend_y-0.4]],
                             facecolor=COLORS['arrow'], edgecolor=COLORS['arrow'],
                             linewidth=1, zorder=5)
    ax.add_patch(diamond2)
    ax.annotate('', xy=(legend_x+0.6, legend_y-0.4), xytext=(legend_x, legend_y-0.4),
                arrowprops=dict(arrowstyle='->', color=COLORS['arrow'], lw=1.5), zorder=5)
    ax.text(legend_x+0.7, legend_y-0.4, '组合 (composition)', fontsize=7.5, va='center')

    plt.tight_layout(pad=1.5)
    plt.savefig('/home/wmh/Documents/trae_projects/trace_path/docs/class_diagram.png',
                dpi=150, bbox_inches='tight', facecolor='#FAFAFA')
    plt.close()
    print("✓ class_diagram.png saved")


# ============================================================
# 2. SEQUENCE DIAGRAM - Location Update Flow
# ============================================================
def generate_sequence_diagram():
    fig, ax = plt.subplots(figsize=(20, 13))
    ax.set_xlim(0, 20)
    ax.set_ylim(0, 13)
    ax.axis('off')
    ax.set_facecolor('#FAFAFA')
    fig.patch.set_facecolor('#FAFAFA')

    ax.text(10, 12.5, 'trace_path 定位更新时序图', ha='center', va='center',
            fontsize=16, fontweight='bold', color='#1565C0')
    ax.text(10, 12.1, 'Location Update Sequence Diagram', ha='center', va='center',
            fontsize=10, color='#757575', style='italic')

    # Participants (lifelines)
    participants = [
        ('用户\nUser', 2.0),
        ('Background\nLocationService', 5.5),
        ('Location\nProvider', 8.5),
        ('GPS/Network', 11.0),
        ('Track\nRecorder', 13.5),
        ('Compressed\nTrackStorage', 16.5),
    ]

    p_colors = ['#1565C0', '#0277BD', '#00695C', '#E65100', '#1565C0', '#2E7D32']

    for (name, x), color in zip(participants, p_colors):
        ax.plot([x, x], [1.5, 11.0], color=color, linewidth=1.5,
                linestyle='-', zorder=2)
        # Actor box
        rect = FancyBboxPatch((x-0.8, 11.0), 1.6, 0.55,
                               boxstyle="round,pad=0.05",
                               facecolor=color, edgecolor='none', zorder=3)
        ax.add_patch(rect)
        ax.text(x, 11.27, name, ha='center', va='center', fontsize=7.5,
                fontweight='bold', color='white', zorder=4)

    # Activation bars (small horizontal at top of lifelines)
    def activation_bar(x, y_top, height, color):
        rect = FancyBboxPatch((x-0.08, y_top), 0.16, height,
                               boxstyle="round,pad=0.02",
                               facecolor=color, edgecolor='none',
                               linewidth=0, alpha=0.4, zorder=2)
        ax.add_patch(rect)

    # ---- MESSAGES ----
    def msg(ax, x1, y1, x2, y2, label, color='#424242', dashed=False,
            label_offset_y=0.08):
        ls = 'dashed' if dashed else 'solid'
        ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                    arrowprops=dict(arrowstyle='->', color=color, lw=1.4,
                                   linestyle=ls, connectionstyle='arc3,rad=0'),
                    zorder=3)
        mx = (x1 + x2) / 2
        my = (y1 + y2) / 2 + label_offset_y
        ax.text(mx, my, label, ha='center', va='bottom', fontsize=7.2,
                color=color, zorder=6,
                bbox=dict(boxstyle='round,pad=0.12', facecolor='white',
                         edgecolor='none', alpha=0.85))

    def ret_msg(ax, x1, y1, x2, y2, label='', color='#9E9E9E'):
        ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                    arrowprops=dict(arrowstyle='->', color=color, lw=1.1,
                                   linestyle='dashed', connectionstyle='arc3,rad=0'),
                    zorder=3)
        if label:
            mx = (x1 + x2) / 2
            my = (y1 + y2) / 2 - 0.12
            ax.text(mx, my, label, ha='center', va='top', fontsize=6.8,
                    color=color, zorder=6,
                    bbox=dict(boxstyle='round,pad=0.1', facecolor='white',
                             edgecolor='none', alpha=0.8))

    # Row 1: start() from User
    y = 10.6
    msg(ax, 2.0, y, 5.5, y, 'start()', color='#1565C0')
    activation_bar(5.5, y-0.55, 0.55, '#0277BD')

    # Step 2: check permission
    y = 10.0
    msg(ax, 5.5, y, 8.5, y, 'checkPermission()', color='#0277BD')
    ret_msg(ax, 8.5, y-0.15, 5.5, y-0.35, 'bool')

    # Step 3: start native foreground service
    y = 9.4
    msg(ax, 5.5, y, 5.5, y-0.2, 'start native service\n(通知栏保活)', color='#0277BD')
    # Native service (no response arrow shown)

    # Step 4: start location loop
    y = 8.8
    msg(ax, 5.5, y, 5.5, y-0.2, '_startLocationLoop()', color='#757575')

    # Step 5: fetch location
    y = 8.2
    msg(ax, 5.5, y, 8.5, y, 'getCurrentPosition()', color='#0277BD')
    activation_bar(8.5, y-0.4, 0.4, '#00695C')

    # Step 6: GPS try
    y = 7.6
    msg(ax, 8.5, y, 11.0, y, 'GPS.getCurrentPosition()', color='#E65100')
    ret_msg(ax, 11.0, y-0.15, 8.5, y-0.35, 'Position / null')

    # Step 7: fallback to network
    y = 7.0
    msg(ax, 8.5, y, 11.0, y, 'Network.getCurrentPosition()', color='#E65100', dashed=True)
    ret_msg(ax, 11.0, y-0.15, 8.5, y-0.35, 'Position / null', color='#9E9E9E')

    # Step 8: return to FBLS
    y = 6.4
    ret_msg(ax, 8.5, y, 5.5, y+0.2, 'Position?')

    # Step 9: broadcast to subscribers
    y = 5.8
    msg(ax, 5.5, y, 5.5, y-0.2, '_broadcast(LocationEvent)', color='#0277BD')

    # Step 10: record (save to local)
    y = 5.2
    msg(ax, 5.5, y, 13.5, y, 'TrackRecorder().record()', color='#0277BD')
    activation_bar(13.5, y-0.4, 0.4, '#1565C0')

    # Step 11: write
    y = 4.6
    msg(ax, 13.5, y, 16.5, y, 'write(phone, TrackPoint)', color='#1565C0')
    activation_bar(16.5, y-0.4, 0.4, '#2E7D32')

    # Step 12: write bytes to file
    y = 4.0
    msg(ax, 16.5, y, 16.5, y-0.2, 'append .dat file', color='#2E7D32')
    ret_msg(ax, 16.5, y-0.4, 13.5, y-0.6, '')

    # Step 13: schedule next
    y = 3.4
    msg(ax, 5.5, y, 5.5, y-0.2, '_scheduleNextLocation()', color='#757575')

    # Step 14: GPS retry flow (alt path)
    y = 2.8
    msg(ax, 5.5, y, 5.5, y-0.2, '_scheduleGpsRetry()\n(指数退避重试)', color='#E65100', dashed=True)

    # Notes box
    note_text = ('📱 定位流程说明:\n'
                 '① start() 触发权限检查 + 原生保活\n'
                 '② 定时器触发 → getCurrentPosition\n'
                 '③ GPS 优先 (60% 超时)，失败则 Network fallback\n'
                 '④ 定位成功: 广播 → 存储 → 调度下次\n'
                 '⑤ 定位失败: 指数退避重试 (最多5次)\n'
                 '⑥ GPS 重试: 15s→30s→60s→120s→240s (上限5分钟)')
    ax.text(0.4, 2.2, note_text, fontsize=7.2, va='top',
            bbox=dict(boxstyle='round,pad=0.4', facecolor='#FFF8E1',
                     edgecolor='#FFD54F', linewidth=1),
            zorder=5)

    plt.tight_layout(pad=1.5)
    plt.savefig('/home/wmh/Documents/trae_projects/trace_path/docs/sequence_diagram.png',
                dpi=150, bbox_inches='tight', facecolor='#FAFAFA')
    plt.close()
    print("✓ sequence_diagram.png saved")


# ============================================================
# 3. ARCHITECTURE DIAGRAM - Module Layering
# ============================================================
def generate_architecture_diagram():
    fig, ax = plt.subplots(figsize=(18, 12))
    ax.set_xlim(0, 18)
    ax.set_ylim(0, 12)
    ax.axis('off')
    ax.set_facecolor('#ECEFF1')
    fig.patch.set_facecolor('#ECEFF1')

    ax.text(9, 11.5, 'trace_path 架构分层图', ha='center', va='center',
            fontsize=16, fontweight='bold', color='#1565C0')
    ax.text(9, 11.1, 'Architecture Layer Diagram', ha='center', va='center',
            fontsize=10, color='#757575', style='italic')

    layer_colors = {
        'presentation': ('#E3F2FD', '#1565C0'),
        'business':     ('#E8F5E9', '#2E7D32'),
        'service':      ('#FFF3E0', '#E65100'),
        'data':         ('#FCE4EC', '#AD1457'),
        'native':       ('#EDE7F6', '#6A1B9A'),
    }

    def draw_layer(ax, x, y, w, h, title, title_color, items, bg_color, border_color):
        # Layer background
        rect = FancyBboxPatch((x, y), w, h,
                                boxstyle="round,pad=0.15",
                                facecolor=bg_color,
                                edgecolor=border_color,
                                linewidth=2,
                                zorder=2)
        ax.add_patch(rect)

        # Title bar
        title_h = 0.45
        title_rect = FancyBboxPatch((x, y+h-title_h), w, title_h,
                                     boxstyle="round,pad=0.05",
                                     facecolor=border_color,
                                     edgecolor='none',
                                     linewidth=0, zorder=3)
        ax.add_patch(title_rect)
        ax.text(x+w/2, y+h-title_h/2, title, ha='center', va='center',
                fontsize=9.5, fontweight='bold', color='white', zorder=4)

        # Items
        item_h = 0.38
        start_y = y + h - title_h - 0.2
        for i, item in enumerate(items):
            iy = start_y - i * item_h
            if iy < y + 0.1:
                break
            ax.text(x + 0.2, iy, f'• {item}', ha='left', va='center',
                    fontsize=8, color='#212121', zorder=4)

    # Draw layers (bottom to top = native to presentation)
    layers = [
        # (x, y, w, h, title, items, key)
        (0.5, 0.4, 17, 2.0, '📦 Presentation Layer（表现层）',
         ['HomePage / GuardPage / LoginPage / MinePage / TrackPage',
          'LocationPage / TrackMapPage / PermissionSettingsPage',
          'UserLocationMarker · LocationSettingsDialog'],
         'presentation'),

        (0.5, 2.6, 17, 1.8, '⚙️ Business Logic Layer（业务逻辑层）',
         ['BackgroundLocationService（定位中枢，单例）',
          'TrackRecorder（轨迹录制，单例） · FriendService（好友管理）',
          'LocationSettingsService（设置持久化） · ErrorLoggerService（日志）'],
         'business'),

        (0.5, 4.6, 17, 2.0, '🔧 Service Abstraction Layer（服务抽象层）',
         ['LocationProvider（抽象接口）← GeolocatorLocationProvider / NativeLocationProvider',
          'TrackStorage（抽象接口）← CompressedTrackStorage / LocalCsvStorage',
          'FriendStorage（抽象接口）← FileBasedFriendStorage · UserStorage ← FileBasedUserStorage'],
         'service'),

        (0.5, 6.8, 17, 1.6, '💾 Data Access Layer（数据访问层）',
         ['CompressedTrackStorage（二进制 Protobuf 编码，默认）',
          'LocalCsvStorage（CSV 明文存储，可切换）',
          'FileBasedFriendStorage · FileBasedUserStorage（JSON 文件）'],
         'data'),

        (0.5, 8.6, 17, 1.8, '🔌 Native Platform Layer（原生平台层）',
         ['Android: LocationForegroundService（通知栏前台保活）',
          'Android: FusedLocationProviderClient（原生定位）',
          'MethodChannel: com.kenny.trace_path/location_service（Flutter ↔ Native 通信）'],
         'native'),
    ]

    for (x, y, w, h, title, items, key) in layers:
        bg, border = layer_colors[key]
        draw_layer(ax, x, y, w, h, title, border, items, bg, border)

    # Arrows between layers
    arrow_x = 9.0
    for i in range(len(layers)-1):
        y1 = layers[i][2] + layers[i][3]  # bottom of layer i
        y2 = layers[i+1][2]               # top of layer i+1
        mid_y = (y1 + y2) / 2
        ax.annotate('', xy=(arrow_x+0.15, y2+0.05), xytext=(arrow_x-0.15, y1-0.05),
                    arrowprops=dict(arrowstyle='<->', color='#90A4AE', lw=1.8,
                                   connectionstyle='arc3,rad=0'), zorder=5)
        # Label in the middle
        labels = ['UI调用', '依赖抽象', '面向接口', '数据持久化', '平台能力']
        if i < len(labels):
            ax.text(arrow_x+0.5, mid_y, labels[i], ha='left', va='center',
                    fontsize=7, color='#78909C', rotation=90, zorder=6)

    # Arrow legend
    ax.text(15.5, 0.3, '↑ 调用方向', ha='center', fontsize=7.5, color='#90A4AE',
            bbox=dict(boxstyle='round,pad=0.2', facecolor='white', edgecolor='#B0BEC5'))

    plt.tight_layout(pad=1.0)
    plt.savefig('/home/wmh/Documents/trae_projects/trace_path/docs/architecture_diagram.png',
                dpi=150, bbox_inches='tight', facecolor='#ECEFF1')
    plt.close()
    print("✓ architecture_diagram.png saved")


if __name__ == '__main__':
    generate_class_diagram()
    generate_sequence_diagram()
    generate_architecture_diagram()
    print("All UML diagrams generated successfully!")
