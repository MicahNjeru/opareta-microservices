import { Injectable, Inject } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import type { Cache } from 'cache-manager';
import { CACHE_MANAGER } from '@nestjs/cache-manager';

@Injectable()
export class AppService {
  constructor(
    @InjectDataSource()
    private dataSource: DataSource,
    @Inject(CACHE_MANAGER) private cacheManager: Cache,
  ) {}

  async getHealth() {
    const dbHealthy = this.dataSource.isInitialized;
    
    let redisHealthy = false;
    try {
      await this.cacheManager.set('health-check', 'ok', 1000);
      const result = await this.cacheManager.get('health-check');
      redisHealthy = result === 'ok';
    } catch (error) {
      redisHealthy = false;
    }

    return {
      status: dbHealthy && redisHealthy ? 'ok' : 'error',
      timestamp: new Date().toISOString(),
      service: 'payment-service',
      database: dbHealthy ? 'connected' : 'disconnected',
      redis: redisHealthy ? 'connected' : 'disconnected',
    };
  }
}