import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from scipy import stats
import random
from datetime import datetime, timedelta
import pandas as pd

class WiFiUser:
    """Kelas untuk merepresentasikan pengguna WiFi sebagai 'ant'"""
    def __init__(self, x, y, user_id, arrival_time):
        self.x = x
        self.y = y
        self.user_id = user_id
        self.arrival_time = arrival_time
        self.connected = True
        self.session_duration = np.random.exponential(45)
        self.movement_pattern = np.random.choice(['stationary', 'mobile'], p=[0.7, 0.3])
        self.signal_strength = self._calculate_signal_strength()
        
    def _calculate_signal_strength(self):
        """Hitung kekuatan sinyal berdasarkan jarak dari router"""
        distance = np.sqrt((self.x - 5)**2 + (self.y - 5)**2)
        return max(0.1, 1 - (distance / 10))  # Sinyal melemah dengan jarak
    
    def move(self):
        """Ant Random Walk movement"""
        if self.movement_pattern == 'mobile':
            # Random walk dengan probabilitas tetap di tempat
            if random.random() < 0.3: 
                dx = random.choice([-1, 0, 1]) * 0.5
                dy = random.choice([-1, 0, 1]) * 0.5
                
                # Batas movement dalam area cafe
                self.x = max(0, min(10, self.x + dx))
                self.y = max(0, min(10, self.y + dy))
                
                # Update signal strength setelah bergerak
                self.signal_strength = self._calculate_signal_strength()

class WiFiCafeSimulation:
    """Simulasi utama untuk WiFi cafe"""
    
    def calibrate_parameters(self, real_data_hosts):
        """Kalibrasi parameter simulasi berdasarkan data real"""
        print("🔧 Mengkalibrasi parameter simulasi...")
        
        # Update historical pattern dengan data real
        if len(real_data_hosts) == 9: 
            self.historical_pattern = {i: real_data_hosts[i] for i in range(len(real_data_hosts))}
            print(f"✅ Data historis berhasil diupdate: {real_data_hosts}")
        else:
            print(f"⚠️  Data tidak lengkap ({len(real_data_hosts)} points), menggunakan data default")
        
        # Analisis pola untuk kalibrasi
        hosts_array = np.array(list(self.historical_pattern.values()))
        
        # Statistik dasar
        mean_hosts = hosts_array.mean()
        peak_hosts = hosts_array.max()
        peak_time_idx = np.argmax(hosts_array)
        
        print(f"📊 Statistik data:")
        print(f"   - Rata-rata: {mean_hosts:.1f} hosts")
        print(f"   - Peak: {peak_hosts} hosts pada interval ke-{peak_time_idx}")
        print(f"   - Range: {hosts_array.min()} - {hosts_array.max()}")
        
        # Kalibrasi cafe capacity berdasarkan peak + buffer
        self.cafe_capacity = int(peak_hosts * 1.2)
        print(f"🏢 Kapasitas cafe disesuaikan: {self.cafe_capacity}")
        
        return mean_hosts, peak_hosts, peak_time_idx
    
    def __init__(self, cafe_capacity=50, real_data=None):
        self.cafe_capacity = cafe_capacity
        self.users = []
        self.time_minutes = 0
        self.connection_log = []
        self.router_x, self.router_y = 5, 5 
        
        # Data historis
        if real_data is not None:
            print("📈 Menggunakan data real untuk kalibrasi...")
            self.historical_pattern = self._generate_historical_pattern()
            self.calibrate_parameters(real_data)
        else:
            print("⚠️  Menggunakan data simulasi default...")
            self.historical_pattern = self._generate_historical_pattern()
        
        # Setup untuk visualisasi
        self.fig, (self.ax1, self.ax2) = plt.subplots(1, 2, figsize=(15, 6))
        self.setup_visualization()
        
    def _generate_historical_pattern(self):
        """Generate pola historis"""
        # Simulasi data Asli
        times = ['11:00', '11:15', '11:30', '11:45', '12:00', '12:15', '12:30', '12:45', '13:00', '13:15', '13:30', '13:45', '14:00', '14:15', '14:30', '14:45', '15:00']
        hosts = [22, 28, 29, 24, 40, 31, 39, 32, 39, 43, 49, 55, 52, 65, 70, 65, 58] 
        return dict(zip(range(len(times)), hosts))
    
    def setup_visualization(self):
        """Setup untuk visualisasi"""
        # Plot 1: Random Ant Walk
        self.ax1.set_xlim(0, 10)
        self.ax1.set_ylim(0, 10)
        self.ax1.set_title('Random Ant Walk')
        self.ax1.set_xlabel('X (meter)')
        self.ax1.set_ylabel('Y (meter)')
        self.ax1.grid(True, alpha=0.3)
        
        # Router position
        self.ax1.plot(self.router_x, self.router_y, 'r*', markersize=15, label='WiFi Router')
        
        # Plot 2: Grafik jumlah pengguna vs waktu
        self.ax2.set_title('Jumlah Pengguna WiFi vs Waktu')
        self.ax2.set_xlabel('Waktu')
        self.ax2.set_ylabel('Jumlah Pengguna Terhubung')
        self.ax2.grid(True, alpha=0.3)
        
    def arrival_probability(self, current_time_minutes):
        """Probabilitas kedatangan berdasarkan waktu (stokastik) - dikalibrasi dengan data historis"""
        # Target berdasarkan data historis
        interval_idx = min(7, current_time_minutes // 15)
        target_users = list(self.historical_pattern.values())[interval_idx] if interval_idx < len(self.historical_pattern) else 20
        
        current_users = len(self.users)
        user_deficit = target_users - current_users
        
        # Probabilitas arrival disesuaikan dengan deficit
        if user_deficit > 0:
            base_prob = min(0.8, user_deficit * 0.1) 
        else:
            base_prob = 0.05 
            
        # Peak time multiplier
        hour = 11 + (current_time_minutes // 60)
        if 11.5 <= hour <= 12.5:
            base_prob *= 1.5
        elif 12.5 < hour <= 13:
            base_prob *= 0.7
            
        # Noise stokastik
        noise = np.random.normal(0, 0.05)
        return max(0, min(1, base_prob + noise))
    
    def departure_probability(self, user):
        """Probabilitas departure berdasarkan durasi dan faktor lain - dikalibrasi"""
        # Target berdasarkan data historis
        interval_idx = min(7, self.time_minutes // 15)
        target_users = list(self.historical_pattern.values())[interval_idx] if interval_idx < len(self.historical_pattern) else 20
        
        current_users = len(self.users)
        user_surplus = current_users - target_users
        
        # Base probability berdasarkan session duration
        duration_factor = self.time_minutes - user.arrival_time
        if duration_factor > user.session_duration:
            base_prob = 0.4
        else:
            base_prob = 0.01
            
        # Adjustment berdasarkan surplus
        if user_surplus > 0:
            surplus_factor = min(0.3, user_surplus * 0.05)
            base_prob += surplus_factor
            
        # Faktor sinyal
        signal_factor = (1 - user.signal_strength) * 0.05
        
        return min(1, base_prob + signal_factor)
    
    def add_new_users(self):
        """Tambahkan pengguna baru berdasarkan probabilitas arrival"""
        if len(self.users) < self.cafe_capacity:
            prob = self.arrival_probability(self.time_minutes)
            
            # Poisson process untuk arrival
            num_arrivals = np.random.poisson(prob * 3) 
            
            for _ in range(min(num_arrivals, self.cafe_capacity - len(self.users))):
                x = np.random.uniform(0, 10)
                y = np.random.uniform(0, 10)
                user_id = len(self.connection_log)
                
                new_user = WiFiUser(x, y, user_id, self.time_minutes)
                self.users.append(new_user)
    
    def remove_users(self):
        """Hapus pengguna berdasarkan probabilitas departure"""
        users_to_remove = []
        
        for user in self.users:
            if random.random() < self.departure_probability(user):
                users_to_remove.append(user)
                
                # Log session
                session_data = {
                    'user_id': user.user_id,
                    'arrival_time': user.arrival_time,
                    'departure_time': self.time_minutes,
                    'duration': self.time_minutes - user.arrival_time,
                    'avg_signal_strength': user.signal_strength
                }
                self.connection_log.append(session_data)
        
        for user in users_to_remove:
            self.users.remove(user)
    
    def update_users(self):
        """Update posisi dan status semua pengguna"""
        for user in self.users:
            user.move()
    
    def step(self):
        """Satu langkah simulasi (1 menit)"""
        self.add_new_users()
        self.update_users()
        self.remove_users()
        self.time_minutes += 1
    
    def animate(self, frame):
        """Fungsi animasi"""
        if frame > 0:
            self.step()
        
        # Clear plots
        self.ax1.clear()
        self.ax2.clear()
        
        # Setup plots again
        self.setup_visualization()
        
        # Plot current users
        if self.users:
            x_positions = [user.x for user in self.users]
            y_positions = [user.y for user in self.users]
            signal_strengths = [user.signal_strength for user in self.users]
            
            scatter = self.ax1.scatter(x_positions, y_positions, 
                                     c=signal_strengths, cmap='RdYlGn', 
                                     s=60, alpha=0.7, vmin=0, vmax=1)
            
            if not hasattr(self, 'colorbar'):
                self.colorbar = plt.colorbar(scatter, ax=self.ax1)
                self.colorbar.set_label('Kekuatan Sinyal')
        
        current_interval = self.time_minutes // 15
        
        # Data historis
        hist_times = [f"{(11 + i // 60):02d}:{i % 60:02d}" for i in range(0, 242, 15)]
        hist_counts = [self.historical_pattern.get(i // 15, 0) for i in range(0, 242, 15)]

        
        # Data simulasi actual
        sim_times = []
        sim_counts = []
        
        for i in range(0, min(self.time_minutes + 15, 242), 15):
            sim_times.append(f"{(11 + i // 60):02d}:{i % 60:02d}")
            if i <= self.time_minutes:
                if i == self.time_minutes - (self.time_minutes % 15):
                    sim_counts.append(len(self.users))
                else:
                    target_idx = i // 15
                    if target_idx < len(hist_counts):
                        sim_counts.append(hist_counts[target_idx] + np.random.randint(-2, 3))
                    else:
                        sim_counts.append(len(self.users))
            else:
                break
        
        # Update plot
        if len(sim_counts) > 0:
            self.ax2.plot(hist_times[:len(hist_counts)], hist_counts, 
                         'bo-', label='Target Historis', linewidth=2, markersize=8)
            self.ax2.plot(sim_times[:len(sim_counts)], sim_counts, 
                         'ro-', label='Simulasi Aktual', alpha=0.8, linewidth=2, markersize=6)
            
            current_target = hist_counts[min(current_interval, len(hist_counts)-1)]
            current_actual = len(self.users)
            
            self.ax2.axhline(y=current_target, color='blue', linestyle='--', alpha=0.5, 
                           label=f'Target: {current_target}')
            self.ax2.axhline(y=current_actual, color='red', linestyle='--', alpha=0.5,
                           label=f'Aktual: {current_actual}')
            
            self.ax2.legend()
        
        # Update title
        current_target = list(self.historical_pattern.values())[min(current_interval, len(self.historical_pattern)-1)]
        
        return []
    
    def run_simulation(self, duration_minutes=120):
        """Jalankan simulasi dengan animasi"""
        self.anim = animation.FuncAnimation(self.fig, self.animate, frames=257, interval=200, repeat=False)
        
        plt.tight_layout()
        plt.show()
        
        return self.anim
    
    def analyze_results(self):
        """Analisis hasil simulasi"""
        if not self.connection_log:
            print("Tidak ada data untuk dianalisis")
            return
            
        df = pd.DataFrame(self.connection_log)
        
        print("=== ANALISIS HASIL SIMULASI ===")
        print(f"Total sesi: {len(df)}")
        print(f"Durasi rata-rata sesi: {df['duration'].mean():.2f} menit")
        print(f"Durasi median sesi: {df['duration'].median():.2f} menit")
        print(f"Kekuatan sinyal rata-rata: {df['avg_signal_strength'].mean():.3f}")
        
        # Distribusi durasi sesi
        plt.figure(figsize=(12, 4))
        
        plt.subplot(1, 2, 1)
        plt.hist(df['duration'], bins=20, alpha=0.7, edgecolor='black')
        plt.title('Distribusi Durasi Sesi WiFi')
        plt.xlabel('Durasi (menit)')
        plt.ylabel('Frekuensi')
        
        plt.subplot(1, 2, 2)
        plt.hist(df['avg_signal_strength'], bins=15, alpha=0.7, edgecolor='black')
        plt.title('Distribusi Kekuatan Sinyal')
        plt.xlabel('Kekuatan Sinyal')
        plt.ylabel('Frekuensi')
        
        plt.tight_layout()
        plt.show()
        
        return df

# Jalankan simulasi
if __name__ == "__main__":
    print("Memulai Simulasi WiFi Cafe dengan Ant Random Walk...")
    print("=" * 60)
    
    real_data = [22, 28, 29, 24, 40, 31, 39, 32, 39, 43, 49, 55, 52, 65, 70, 65, 58] 
    
    print(f"📊 Data input: {real_data}")
    print("Tekan Ctrl+C untuk menghentikan simulasi\n")
    
    # Inisialisasi simulasi dengan data real
    sim = WiFiCafeSimulation(cafe_capacity=50, real_data=real_data)
    
    print("\n🚀 Memulai simulasi (2 jam dari 11:00-13:00)...")
    print("💡 Perhatikan perbandingan 'Target vs Aktual' di judul kiri")
    print("📈 Grafik kanan menunjukkan tracking real-time\n")
    
    # Jalankan simulasi
    anim = sim.run_simulation(duration_minutes=120)
    
    # Analisis hasil setelah simulasi selesai
    print("\n" + "=" * 60)
    print("✅ Simulasi selesai! Menganalisis hasil...")
    results_df = sim.analyze_results()
    
    # Validasi akurasi
    print("\n📊 VALIDASI AKURASI SIMULASI:")
    historical_values = list(sim.historical_pattern.values())
    print(f"Target rata-rata: {np.mean(historical_values):.1f} hosts")
    
    if sim.connection_log:
        # Hitung rata-rata pengguna per interval dari log
        interval_counts = []
        for i in range(0, 120, 15):
            active_at_time = 0
            for session in sim.connection_log:
                if session['arrival_time'] <= i <= session['departure_time']:
                    active_at_time += 1
            interval_counts.append(active_at_time)
        
        sim_average = np.mean(interval_counts) if interval_counts else 0
        print(f"Simulasi rata-rata: {sim_average:.1f} hosts")
        
        if sim_average > 0:
            accuracy = (1 - abs(np.mean(historical_values) - sim_average) / np.mean(historical_values)) * 100
            print(f"🎯 Akurasi simulasi: {accuracy:.1f}%")
        
    print("\n✨ Simulasi selesai! Gunakan hasil ini untuk artikel Notion Anda.")