/** 每个资源一个请求代数。连续切换选项时，旧响应绝不能覆盖新页面。 */
export class RequestGate {
  private generation = 0;
  next(): number { return ++this.generation; }
  isCurrent(value: number): boolean { return value === this.generation; }
  invalidate(): void { ++this.generation; }
}
